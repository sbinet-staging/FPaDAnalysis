void diagnostics(const char *inFile, const char *outFile) {
    TFile outputFile(outFile, "recreate");

    auto reader = IOIMPL::LCFactory::getInstance()->createLCReader();
    reader->open(inFile);

    TH1I truthElectronEtaHist("truthElectronEtaHist", "Truth Electron, PT > 1; Eta; Count", 100, -5, 5);
    TH1I pfoElectronEtaHist("pfoElectronEtaHist", "PFO Electron, PT > 1; Eta; Count", 100, -5, 5);
TH2I resPT("resPT","",500,0,50,900,-4,5);

    EVENT::LCEvent *event;
    while ((event = reader->readNextEvent()) != 0) {
        auto truthColl = event->getCollection("MCParticle");
        auto pfoColl = event->getCollection("PandoraPFOCollection");

        double truthElectronP[3] = {0};
        for (int i = 0; i < truthColl->getNumberOfElements(); i++) {
            auto element = (EVENT::MCParticle *)truthColl->getElementAt(i);

            if (element->getGeneratorStatus() == 1) {
                auto p = element->getMomentum();

		if (abs(element->getPDG()) == 11)
			for (int j = 0; j < 3; j++) truthElectronP[j] += p[j];
            }
        }

        double pfoElectronP[3] = {0};
        for (int i = 0; i < pfoColl->getNumberOfElements(); i++) {
            auto element = (EVENT::ReconstructedParticle *)pfoColl->getElementAt(i);
		auto p = element->getMomentum();

            if (abs(element->getType()) == 11) {

                for (int j = 0; j < 3; j++) pfoElectronP[j] += p[j];
            }
        }

        double truthElectronPL = truthElectronP[2];
        double truthElectronPT = sqrt(pow(truthElectronP[0], 2) + pow(truthElectronP[1], 2));
        double truthElectronPMag =
            sqrt(pow(truthElectronP[0], 2) + pow(truthElectronP[1], 2) + pow(truthElectronP[2], 2));
        double truthElectronEta = atanh(truthElectronPL / truthElectronPMag);

        double pfoElectronPL = pfoElectronP[2];
        double pfoElectronPT = sqrt(pow(pfoElectronP[0], 2) + pow(pfoElectronP[1], 2));
        double pfoElectronPMag =
            sqrt(pow(pfoElectronP[0], 2) + pow(pfoElectronP[1], 2) + pow(pfoElectronP[2], 2));
        double pfoElectronEta = atanh(pfoElectronPL / pfoElectronPMag);

        if (truthElectronPT > 1) {
            truthElectronEtaHist.Fill(truthElectronEta);
            pfoElectronEtaHist.Fill(pfoElectronEta);
        }

	resPT.Fill(truthElectronPT,pfoElectronPT/truthElectronPT);
    }

    truthElectronEtaHist.Write();
    pfoElectronEtaHist.Write();
    resPT.Write();

    outputFile.Close();
}
