import WhisperKit

let pipe = try? WhisperKit()
let callback: (TranscriptionProgress) -> Bool = { _ in return true }
