import Foundation
import Vision
import AppKit

/// This class handles the actual "reading" of text from an image.
/// It uses Apple's Vision framework, which is built-in and very powerful.
class OCREngine {
    
    /// Performs OCR on an NSImage and returns a list of results.
    /// Since OCR can take a moment, we use a completion handler to return the results.
    func performOCR(on image: NSImage, completion: @escaping ([OCRResult]) -> Void) {
        // 1. Convert NSImage to a format Vision can understand (CGImage)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Error: Could not convert NSImage to CGImage")
            completion([])
            return
        }
        
        // 2. Create the request that tells Vision to "recognize text"
        let request = VNRecognizeTextRequest { (request, error) in
            if let error = error {
                print("OCR Error: \(error)")
                completion([])
                return
            }
            
            // 3. Process the results when the scan is finished
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }
            
            var results: [OCRResult] = []
            
            // For each block of text Vision found...
            for observation in observations {
                // Get the top candidate (Vision provides multiple guesses)
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                
                // Vision bounding boxes are "normalized" (values from 0.0 to 1.0)
                // and use a bottom-left origin. We need to convert them to
                // coordinate space relative to the image size.
                let box = observation.boundingBox
                
                // Convert normalized Vision coordinates to actual pixel/point coordinates
                // Vision: Origin Bottom-Left, 0.0 to 1.0
                // Our Screen Space: Origin Top-Left (usually), actual sizes
                // Note: We'll do the final coordinate mapping in the View or Manager
                // once we know the image's actual display size.
                
                let result = OCRResult(
                    text: topCandidate.string,
                    bounds: AppRect(
                        x: box.origin.x * image.size.width,
                        y: (1 - box.origin.y - box.size.height) * image.size.height, // Flip Y for top-left origin
                        width: box.size.width * image.size.width,
                        height: box.size.height * image.size.height
                    )
                )
                results.append(result)
            }
            
            // Return the finished list on the main thread (for UI updates)
            DispatchQueue.main.async {
                completion(results)
            }
        }
        
        // 4. Configure the request (optional tweaks)
        request.recognitionLevel = .fast // More performant for continuous scanning
        request.usesLanguageCorrection = true
        
        // 5. Run the request using an Image Request Handler
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform OCR: \(error)")
                DispatchQueue.main.async { completion([]) }
            }
        }
    }
}
