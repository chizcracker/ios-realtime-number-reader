/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 The utilities for dealing with recognized strings.
 */

import Foundation

extension Character {
    
    // Given a list of allowed characters, try to convert self to those in the list
    // if not already in it. This method handles some common misclassifications for
    // characters that are visually similar and can only be correctly recognized
    // with more context or domain knowledge. Here are some examples, which should be
    // read in Menlo or some other font that has different symbols for all characters:
    // 1 and l are the same character in Times New Roman.
    // I and l are the same character in Helvetica.
    // 0 and O are extremely similar in many fonts.
    // oO, wW, cC, sS, pP and others only differ by size in many fonts.
    func getSimilarCharacterIfNotIn(allowedChars: String) -> Character {
        let conversionTable = [
            "s": "S",
            "S": "5",
            "5": "S",
            "o": "O",
            "Q": "O",
            "O": "0",
            "0": "O",
            "l": "I",
            "I": "1",
            "1": "I",
            "B": "8",
            "8": "B"
        ]
        // Allow a maximum of two substitutions to handle 's' -> 'S' -> '5'.
        let maxSubstitutions = 2
        var current = String(self)
        var counter = 0
        while !allowedChars.contains(current) && counter < maxSubstitutions {
            if let altChar = conversionTable[current] {
                current = altChar
                counter += 1
            } else {
                // Doesn't match anything in our table. Give up.
                break
            }
        }
        
        return current.first!
    }
}

extension String {
    func extractNumber() -> (Range<String.Index>, String)? {
        print("Input: \(self)")
        
        guard let range = self.range(of: "\\S+\\s+\\S+", options: .regularExpression, range: nil, locale: nil) else {
            // No phone number found.
            return nil
        }
        
        // Substitute commonly misrecognized characters, for example: 'S' -> '5'
        // or 'l' -> '1'.
        var result = ""
        let allowedChars = " 0123456789"
        for var char in self {
            char = char.getSimilarCharacterIfNotIn(allowedChars: allowedChars)
            if(allowedChars.contains(char)) {
                result.append(char)
            }
        }
        
        // Must have meaningful digits.
        guard result.count > 0 else {
            return nil
        }
        
        print("Sanitized: \(result)")
        return (range, result)
    }
}

class StringTracker {
    var frameIndex: Int64 = 0
    
    typealias StringObservation = (lastSeen: Int64, count: Int64)
    
    // The dictionary of seen strings, used to get stable recognition before
    // displaying anything.
    var seenStrings = [String: StringObservation]()
    var bestCount = Int64(0)
    var bestString = ""
    
    func logFrame(strings: [String]) {
        for string in strings {
            if seenStrings[string] == nil {
                seenStrings[string] = (lastSeen: Int64(0), count: Int64(-1))
            }
            seenStrings[string]?.lastSeen = frameIndex
            seenStrings[string]?.count += 1
            print("Seen \(string) \(seenStrings[string]?.count ?? 0) times")
        }
        
        var obsoleteStrings = [String]()
        
        // Prune old strings and identify the non-pruned string with the
        // greatest count.
        for (string, obs) in seenStrings {
            // Add text not seen in the last 30 frames (~1s) to the
            // obsolete strings array.
            if obs.lastSeen < frameIndex - 30 {
                obsoleteStrings.append(string)
            }
            
            // Find the string with the greatest count.
            let count = obs.count
            if !obsoleteStrings.contains(string) && count > bestCount {
                bestCount = Int64(count)
                bestString = string
            }
        }
        // Remove old strings.
        for string in obsoleteStrings {
            seenStrings.removeValue(forKey: string)
        }
        
        frameIndex += 1
    }
    
    func getStableString() -> String? {
        // Require the recognizer to see the same string at least 10 times.
        if bestCount >= 10 {
            return bestString
        } else {
            return nil
        }
    }
    
    func getCurrentString() -> String? {
        return bestString;
    }
    
    func reset(string: String) {
        seenStrings.removeValue(forKey: string)
        bestCount = 0
        bestString = ""
    }
}
