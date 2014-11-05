//
//  WaitingPenguin.swift
//  swiftpenguins
//
//  Created by Martin Walsh on 05/11/2014.
//  Copyright (c) 2014 Apportable. All rights reserved.
//

import Foundation

class WaitingPenguin: CCSprite {

    func didLoadFromCCB() {
        // Random Delay 0-2 Seconds
        let delay: Double = Double(arc4random_uniform(2000)) / 1000

        // Use Cocos2D Scheduling
        self.scheduleOnce("startBlinkAndJump", delay:delay)
    }

    func startBlinkAndJump() {

        // Start Timeline
        self.animationManager.runAnimationsForSequenceNamed("BlinkAndJump")
    }
    
}