//
//  ViewConfig.swift
//  RealtimeNumberReader
//
//  Created by JEUNG WON KIM on 2/17/24.
//  Copyright © 2024 Apple. All rights reserved.
//

import Foundation
import UIKit

enum ViewConfigPresets {
    case test, toran, ollie
    
    var config: ViewConfig {
        switch self {
        case .test:
            return ViewConfig(
                id: "test",
                borderColor: UIColor.green.cgColor,
                borderWidth: 2,
                startingPosition: CGPoint(x: 200, y: 300), // TODO: change
                startingSize: CGSize(width: 100, height: 200), // TODO: change
                debugLabelPosition: CGPoint(x: 22, y: 33)
            )        case .toran:
            return ViewConfig(
                id: "toran",
                borderColor: UIColor.green.cgColor,
                borderWidth: 2,
                startingPosition: CGPoint(x: 100, y: 300),
                startingSize: CGSize(width: 100, height: 100),
                debugLabelPosition: CGPoint(x: 22, y: 33)
            )
        case .ollie:
            return ViewConfig(
                id: "ollie",
                borderColor: UIColor.blue.cgColor,
                borderWidth: 2,
                startingPosition: CGPoint(x: 220, y: 300),
                startingSize: CGSize(width: 100, height: 100),
                debugLabelPosition: CGPoint(x: 22, y: 58)
            )
        }
    }
}
