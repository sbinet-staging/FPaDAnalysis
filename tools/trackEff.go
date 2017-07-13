package main

import (
	"flag"
	"fmt"
	"image/color"
	"math"
	"os"
	"time"

	"github.com/gonum/plot/vg"
	"go-hep.org/x/hep/hbook"
	"go-hep.org/x/hep/hplot"
	"go-hep.org/x/hep/lcio"
)

var (
	maxFiles       = flag.Int("m", math.MaxInt32, "maximum number of files to process")
	normalize      = flag.Bool("n", false, "normalize Track count to MCParticle count")
	nThreads       = flag.Int("t", 2, "number of concurrent files to process")
	outputPath     = flag.String("o", "out.pdf", "path of output file")
	doMinAnglePlot = flag.Bool("a", false, "generate plot of minimum angle between Tracks and MCParticles")
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

	trueEtaHist := hbook.NewH1D(nEtaBins, minEta, maxEta)
	trackEtaHist := hbook.NewH1D(nEtaBins, minEta, maxEta)
	minAngleHist := hbook.NewH1D(nAngleBins, 0, maxAngle)

	nInputFiles := flag.NArg()
	if nInputFiles > *maxFiles {
		fmt.Println("Stopping at", *maxFiles, "files")
	}

	trueEtaOut := make(chan float64)
	trackEtaOut := make(chan float64)
	minAngleOut := make(chan float64)
	done := make(chan bool)

	nFilesToAnalyze := nInputFiles
	if *maxFiles < nFilesToAnalyze {
		nFilesToAnalyze = *maxFiles
	}

	nSubmitted := 0
	nDone := 0

	for nSubmitted < nFilesToAnalyze && nSubmitted < *nThreads {
		go analyzeFile(flag.Arg(nSubmitted), trueEtaOut, trackEtaOut, minAngleOut, done)
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
					go analyzeFile(flag.Arg(nSubmitted), trueEtaOut, trackEtaOut, minAngleOut, done)
					nSubmitted++
				}
			}
		}
	}

	p, err := hplot.New()
	if err != nil {
		panic(err)
	}
	if *doMinAnglePlot {
		p.X.Label.Text = "minimum angle between Track and MCParticle"
		p.Y.Label.Text = "count"

		h, err := hplot.NewH1D(minAngleHist)
		if err != nil {
			panic(err)
		}
		h.LineStyle.Color = color.RGBA{B: 255, A: 255}
		p.Add(h)
	} else {
		// p.Title.Text = ""
		p.X.Label.Text = "eta"
		p.Y.Label.Text = "count"

		hTrue, err := hplot.NewH1D(trueEtaHist)
		if err != nil {
			panic(err)
		}
		hTrue.LineStyle.Color = color.RGBA{B: 255, A: 255}
		if !*normalize {
			p.Add(hTrue)
		}

		hTrack, err := hplot.NewH1D(trackEtaHist)
		if err != nil {
			panic(err)
		}
		hTrack.LineStyle.Color = color.RGBA{R: 255, A: 255}
		if !*normalize {
			p.Add(hTrack)
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
			hNorm.LineStyle.Color = color.RGBA{B: 255, A: 255}
			p.Add(hNorm)
		}
	}

	p.Save(6*vg.Inch, -1, *outputPath)
}

func analyzeFile(inputPath string, trueEtaOut chan<- float64, trackEtaOut chan<- float64, minAngleOut chan<- float64, done chan<- bool) {
	reader, err := lcio.Open(inputPath)
	if err != nil {
		panic(err)
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
