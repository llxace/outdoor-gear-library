import UIKit

func chooseHistoricalTrack(completion: @escaping (Result<HistoricalTrackImport?, Error>) -> Void) {
    PadFileDialog.pick([.item]) { result in
        do {
            guard let url = try result.get().first else { completion(.success(nil)); return }
            completion(.success(try LibraryTransferFiles.historicalTrack(at: url)))
        } catch { completion(.failure(error)) }
    }
}
