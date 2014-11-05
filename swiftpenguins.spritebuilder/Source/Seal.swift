//
//  Seal.swift
//  swiftpenguins
//
//  Created by Martin Walsh on 02/11/2014.
//  Copyright (c) 2014 Apportable. All rights reserved.
//

import Foundation

class Seal: CCSprite {

    func didLoadFromCCB() {
        self.physicsBody.collisionType = "seal"
    }

    
}