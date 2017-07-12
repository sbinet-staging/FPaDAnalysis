package main

import (
	"fmt"
	"os"

	"go-hep.org/x/hep/lcio"
)

func main() {
	inputPath := os.Args[1]
	//    outputPath := os.Args[2]

	reader, err := lcio.Open(inputPath)
	if err != nil {
		panic(err)
	}
	defer reader.Close()

	for reader.Next() {
		event := reader.Event()
		fmt.Println(event.String())
	}
}
