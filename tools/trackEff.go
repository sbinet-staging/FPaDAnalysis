package main

import (
	"flag"
	"fmt"
	"image/color"
	"io/ioutil"
	"log"
	"math"
	"os"
	"path"
	"time"

	"github.com/gonum/plot/vg"
	"go-hep.org/x/hep/hbook"
	"go-hep.org/x/hep/hplot"
	"go-hep.org/x/hep/lcio"
)

var (
	doMinAnglePlot = flag.Bool("a", false, "generate plot of minimum angle between Tracks and MCParticles")
	inputsAreDirs  = flag.Bool("d", false, "inputs are directories")
	maxFiles       = flag.Int("m", math.MaxInt32, "maximum number of files to process")
	normalize      = flag.Bool("n", false, "normalize Track count to MCParticle count")
	nThreads       = flag.Int("t", 2, "number of concurrent files to process")
	outputPath     = flag.String("o", "out.pdf", "path of output file")
)

const (
	maxAngle   = 0.01
	minEta     = -5
	maxEta     = 5
	nEtaBins   = 50
	nAngleBins = 50
	truthMinPT = 0.5
)

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, `Usage: trackEff [options] <lcio-input-file>
options:
`,
		)
		flag.PrintDefaults()
	}

	flag.Parse()

	p, err := hplot.New()
	if err != nil {
		panic(err)
	}

	p.Title.Text = "Tracking/Truth Comparison for P_T > 0.5 GeV"
	if *normalize {
		p.Title.Text = "Tracking Efficiency for P_T > 0.5 GeV"
	} else if *inputsAreDirs {
		p.Title.Text = "Tracking Comparison for P_T > 0.5 GeV"
	}
	p.Title.Padding = 2 * vg.Millimeter
	p.Legend.Left = true
	p.Legend.Top = true
	p.Legend.Padding = 2 * vg.Millimeter
	p.X.Label.Text = "eta"
	p.Y.Label.Text = "count"
	if *doMinAnglePlot {
		p.Legend.Left = false
		p.X.Label.Text = "min. angular deviation"
		p.Y.Label.Text = "count"
	}

	if *inputsAreDirs {
		for i, dir := range flag.Args() {
			files, err := ioutil.ReadDir(dir)
			if err != nil {
				log.Fatal(err)
			}

			var inputFiles []string
			for _, file := range files {
				inputFiles = append(inputFiles, dir+"/"+file.Name())
			}

			trackColor := color.RGBA{R: 255, B: 255, G: 255, A: 255}
			var dashes []vg.Length
			var dashOffs vg.Length
			switch i {
			case 0:
				trackColor = color.RGBA{B: 255, A: 255}
			case 1:
				trackColor = color.RGBA{R: 255, A: 255}
				dashes = append(dashes, 1*vg.Millimeter)
			case 2:
				trackColor = color.RGBA{G: 255, A: 255}
				dashes = append(dashes, 1*vg.Millimeter)
				dashOffs = 1 * vg.Millimeter
			}

			drawFileSet(inputFiles, p, false, trackColor, path.Base(dir), dashes, dashOffs)
		}
	} else {
		histColor := color.RGBA{R: 255, A: 255}
		if *normalize || *doMinAnglePlot {
			histColor = color.RGBA{B: 255, A: 255}
		}

		drawFileSet(flag.Args(), p, true, histColor, "Track", nil, 0)
	}

	p.Save(6*vg.Inch, 4*vg.Inch, *outputPath)
}

func drawFileSet(inputFiles []string, p *hplot.Plot, drawTruth bool, trackColor color.Color, trackLabel string, trackDashes []vg.Length, trackDashOffs vg.Length) {
	trueEtaHist := hbook.NewH1D(nEtaBins, minEta, maxEta)
	trackEtaHist := hbook.NewH1D(nEtaBins, minEta, maxEta)
	minAngleHist := hbook.NewH1D(nAngleBins, 0, maxAngle)

	trueEtaOut := make(chan float64)
	trackEtaOut := make(chan float64)
	minAngleOut := make(chan float64)
	done := make(chan bool)

	nFilesToAnalyze := len(inputFiles)
	if *maxFiles < nFilesToAnalyze {
		nFilesToAnalyze = *maxFiles
	}

	nSubmitted := 0
	nDone := 0

	for nSubmitted < nFilesToAnalyze && nSubmitted < *nThreads {
		go analyzeFile(inputFiles[nSubmitted], trueEtaOut, trackEtaOut, minAngleOut, done)
		nSubmitted++

		time.Sleep(time.Millisecond)
	}

	for nDone < nSubmitted {
		select {
		case trueEta := <-trueEtaOut:
			trueEtaHist.Fill(trueEta, 1)
		case trackEta := <-trackEtaOut:
			trackEtaHist.Fill(trackEta, 1)
		case minAngle := <-minAngleOut:
			minAngleHist.Fill(minAngle, 1)
		case isDone := <-done:
			if isDone {
				nDone++

				if nSubmitted < nFilesToAnalyze {
					go analyzeFile(inputFiles[nSubmitted], trueEtaOut, trackEtaOut, minAngleOut, done)
					nSubmitted++
				}
			}
		}
	}

	if *doMinAnglePlot {
		h, err := hplot.NewH1D(minAngleHist)
		if err != nil {
			panic(err)
		}
		h.LineStyle.Color = trackColor
		h.LineStyle.Dashes = trackDashes
		h.LineStyle.DashOffs = trackDashOffs
		p.Add(h)
		if *inputsAreDirs {
			p.Legend.Add(trackLabel, h)
		}
	} else {
		if drawTruth {
			hTrue, err := hplot.NewH1D(trueEtaHist)
			if err != nil {
				panic(err)
			}
			hTrue.LineStyle.Color = color.RGBA{B: 255, A: 255}
			if !*normalize {
				p.Add(hTrue)
				p.Legend.Add("MCParticle", hTrue)
			}
		}

		hTrack, err := hplot.NewH1D(trackEtaHist)
		if err != nil {
			panic(err)
		}
		hTrack.LineStyle.Color = trackColor
		hTrack.LineStyle.Dashes = trackDashes
		hTrack.LineStyle.DashOffs = trackDashOffs
		if !*normalize {
			p.Add(hTrack)
			p.Legend.Add(trackLabel, hTrack)
		}

		normEtaHist := hbook.NewH1D(nEtaBins, minEta, maxEta)
		if *normalize {
			for i := 0; i < nEtaBins; i++ {
				trueX, trueY := trueEtaHist.XY(i)
				_, trackY := trackEtaHist.XY(i)
				if trueY > 0 {
					normEtaHist.Fill(trueX, trackY/trueY)
				}
			}

			hNorm, err := hplot.NewH1D(normEtaHist)
			if err != nil {
				panic(err)
			}
			hNorm.LineStyle.Color = trackColor
			hNorm.LineStyle.Dashes = trackDashes
			hNorm.LineStyle.DashOffs = trackDashOffs
			p.Add(hNorm)
			if *inputsAreDirs {
				p.Legend.Add(trackLabel, hNorm)
			}
		}
	}
}

func analyzeFile(inputPath string, trueEtaOut chan<- float64, trackEtaOut chan<- float64, minAngleOut chan<- float64, done chan<- bool) {
	reader, err := lcio.Open(inputPath)
	if err != nil {
		log.Fatal(err)
	}
	defer reader.Close()

	for reader.Next() {
		event := reader.Event()

		truthColl := event.Get("MCParticle").(*lcio.McParticleContainer)
		trackColl := event.Get("Tracks").(*lcio.TrackContainer)

		// FIXME: boost back from crossing angle?

		var pNorms [][3]float64
		for _, truth := range truthColl.Particles {
			if truth.GenStatus != 1 || truth.Charge == float32(0) {
				continue
			}

			pNorm := normalizeVector(truth.P)
			eta := math.Atanh(pNorm[2])
			pT := math.Sqrt(truth.P[0]*truth.P[0] + truth.P[1]*truth.P[1])

			if pT > truthMinPT {
				trueEtaOut <- eta
				pNorms = append(pNorms, pNorm)
			}
		}

		for _, track := range trackColl.Tracks {
			tanLambda := track.TanL()
			eta := -math.Log(math.Sqrt(1+tanLambda*tanLambda) - tanLambda)

			lambda := math.Atan(tanLambda)
			px := math.Cos(track.Phi()) * math.Cos(lambda)
			py := math.Sin(track.Phi()) * math.Cos(lambda)
			pz := math.Sin(lambda)

			pNorm := [3]float64{px, py, pz}

			minAngle := math.Inf(1)
			minIndex := -1
			for i, truePNorm := range pNorms {
				angle := math.Acos(dotProduct(pNorm, truePNorm))
				if angle < minAngle {
					minAngle = angle
					minIndex = i
				}
			}

			if minIndex >= 0 && minAngle < maxAngle {
				trackEtaOut <- eta
				minAngleOut <- minAngle
				pNorms = append(pNorms[:minIndex], pNorms[minIndex+1:]...)
			}
		}
	}

	done <- true
}

func normalizeVector(vector [3]float64) [3]float64 {
	normFactor := math.Sqrt(dotProduct(vector, vector))
	for i, value := range vector {
		vector[i] = value / normFactor
	}
	return vector
}

func phiFromVector(vector [3]float64) float64 {
	rho := math.Sqrt(vector[0]*vector[0] + vector[1]*vector[1])
	if vector[0] >= 0 {
		return math.Asin(vector[1] / rho)
	}
	return -math.Asin(vector[1]/rho) + math.Pi
}

func dotProduct(vector1 [3]float64, vector2 [3]float64) float64 {
	return vector1[0]*vector2[0] + vector1[1]*vector2[1] + vector1[2]*vector2[2]
}
