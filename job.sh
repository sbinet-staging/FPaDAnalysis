#!/bin/bash

bash --login -c "mkdir -p input/$1 output; \
			mv $(basename $2) input/$1/"

bash --login -c "make"

bash --login -c "rm output/$1/*_tracking.slcio output/$1/*_pandora.slcio"

