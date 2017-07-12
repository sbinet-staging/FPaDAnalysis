package main

import (
	"flag"
	"fmt"
	"image/color"
	"math"
	"os"

	"github.com/gonum/plot/vg"
	"go-hep.org/x/hep/hbook"
	"go-hep.org/x/hep/hplot"
	"go-hep.org/x/hep/lcio"
)

var (
	outputPath = flag.String("o", "out.pdf", "path of output file")
	maxFiles   = flag.Int("m", math.MaxInt32, "maximum number of files to process")
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

	trueEtaHist := hbook.NewH1D(100, -5, 5)
	trackEtaHist := hbook.NewH1D(100, -5, 5)

	nInputFiles := flag.NArg()
	if nInputFiles > *maxFiles {
		fmt.Println("Stopping at", *maxFiles, "files")
	}

	for i := 0; i < nInputFiles && i < *maxFiles; i++ {
		inputPath := flag.Arg(i)
		fmt.Println("Processing file: ", inputPath)

		reader, err := lcio.Open(inputPath)
		if err != nil {
			panic(err)
		}
		defer reader.Close()

		for reader.Next() {
			event := reader.Event()

			truthColl := event.Get("MCParticle").(*lcio.McParticleContainer)
			trackColl := event.Get("Tracks").(*lcio.TrackContainer)

			// FIXME: boost back from 7 mrad crossing angle?

			for _, truth := range truthColl.Particles {
				if truth.GenStatus != 1 || truth.Charge == float32(0) {
					continue
				}

				pMag := math.Sqrt(truth.P[0]*truth.P[0] + truth.P[1]*truth.P[1] + truth.P[2]*truth.P[2])
				pL := truth.P[2]
				eta := math.Atanh(pL / pMag)
				trueEtaHist.Fill(eta, 1)
			}

			for _, track := range trackColl.Tracks {
				tanLambda := track.TanL()
				eta := -math.Log(math.Sqrt(1+tanLambda*tanLambda) - tanLambda)
				trackEtaHist.Fill(eta, 1)
			}
		}
	}

	p, err := hplot.New()
	if err != nil {
		panic(err)
	}
	// p.Title.Text = ""
	p.X.Label.Text = "eta"
	p.Y.Label.Text = "count"

	hTrue, err := hplot.NewH1D(trueEtaHist)
	if err != nil {
		panic(err)
	}
	hTrue.LineStyle.Color = color.RGBA{B: 255, A: 255}
	p.Add(hTrue)

	hTrack, err := hplot.NewH1D(trackEtaHist)
	if err != nil {
		panic(err)
	}
	hTrack.LineStyle.Color = color.RGBA{R: 255, A: 255}
	p.Add(hTrack)

	p.Save(6*vg.Inch, -1, *outputPath)
}
