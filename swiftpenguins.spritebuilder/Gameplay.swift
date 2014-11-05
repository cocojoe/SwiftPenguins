//
//  Gameplay.swift
//  swiftpenguins
//
//  Created by Martin Walsh on 02/11/2014.
//  Copyright (c) 2014 Apportable. All rights reserved.
//

import Foundation

class Gameplay: CCNode, CCPhysicsCollisionDelegate {

    // Constants
    let MIN_SPEED: Float = 5;

    // SB Code Connections
    var _physicsNode: CCPhysicsNode?
    var _catapultArm: CCNode?
    var _levelNode: CCNode?
    var _contentNode: CCNode?
    var _pullbackNode: CCNode?
    var _mouseJointNode: CCNode?

    var _mouseJoint: CCPhysicsJoint?
    var _currentPenguin: Penguin?
    var _penguinCatapultJoint: CCPhysicsJoint?
    var _followPenguin: CCAction?

    
    func didLoadFromCCB() {
        self.userInteractionEnabled = true
        
        var level: CCNode = CCBReader.load("Levels/Level1")
        _levelNode!.addChild(level)

        //_physicsNode!.debugDraw = true;
        _physicsNode?.collisionDelegate = self;

        _pullbackNode!.physicsBody.collisionMask = []
        _mouseJointNode!.physicsBody.collisionMask = []
    }


#if os(OSX) // Handle Mouse Input

    override func mouseDown(theEvent: NSEvent) {
        var touchLocation: CGPoint = theEvent.locationInNode(_contentNode)
        self.handleTouchBegan(touchLocation)
    }

    override func mouseDragged(theEvent: NSEvent) {
        var touchLocation: CGPoint = theEvent.locationInNode(_contentNode)
        _mouseJointNode!.position = touchLocation
    }

    override func mouseUp(theEvent: NSEvent) {
        self.releaseCatapult()
    }
#elseif os(iOS) // Handle Touch Input

    override func touchBegan(touch: CCTouch, withEvent event: CCTouchEvent) {
        var touchLocation: CGPoint = touch.locationInNode(_contentNode)
        self.handleTouchBegan(touchLocation)
    }

    override func touchMoved(touch: CCTouch, withEvent event: CCTouchEvent) {
        var touchLocation: CGPoint = touch.locationInNode(_contentNode)
        _mouseJointNode!.position = touchLocation
    }

    override func touchEnded(touch: CCTouch, withEvent event: CCTouchEvent) {
        self.releaseCatapult()
    }

    override func touchCancelled(touch: CCTouch, withEvent event: CCTouchEvent) {
        self.releaseCatapult()
    }

#endif

    func handleTouchBegan(touchLocation: CGPoint) {

        // Begin drag if touch inside catapult arm
        if (CGRectContainsPoint(_catapultArm!.boundingBox(), touchLocation))
        {

            // Move mouse joint position to touch location
            _mouseJointNode!.position = touchLocation

            // Create sprint joint between catapult arm and mouseJointNode
            _mouseJoint = CCPhysicsJoint.connectedSpringJointWithBodyA(_mouseJointNode!.physicsBody, bodyB:_catapultArm!.physicsBody,
                anchorA:ccp(0, 0),
                anchorB:ccp(34, 138),
                restLength:0.0,
                stiffness:3000,
                damping:150)

            // Create Penguin
            _currentPenguin = CCBReader.load("Penguin") as Penguin?

            // Position on Catapult
            var penguinPosition: CGPoint = _catapultArm!.convertToWorldSpace(ccp(34,138))
            _currentPenguin!.position = _physicsNode!.convertToWorldSpace(penguinPosition)

            // Add Penguin to Scene
            _physicsNode?.addChild(_currentPenguin)
            _currentPenguin?.physicsBody.allowsRotation = false

            // Setup Joint, keep penguin attached to catapult while pulling back catapult arm
            _penguinCatapultJoint = CCPhysicsJoint.connectedPivotJointWithBodyA(_currentPenguin!.physicsBody,
                bodyB:_catapultArm!.physicsBody,
                anchorA:_currentPenguin!.anchorPointInPoints)
        }
    }

    func releaseCatapult() {

        if _mouseJoint != nil {

            _mouseJoint?.invalidate()
            _mouseJoint = nil;

            _penguinCatapultJoint?.invalidate()
            _penguinCatapultJoint = nil

            _currentPenguin?.physicsBody.allowsRotation = true;

            _followPenguin = CCActionFollow.actionWithTarget(_currentPenguin, worldBoundary:self.boundingBox()) as CCAction!
            _contentNode!.runAction(_followPenguin)

            _currentPenguin!.launched = true;
        }
    }

    // Collision Handlers
    func ccPhysicsCollisionPostSolve(pair: CCPhysicsCollisionPair!, seal nodeA: CCNode!, wildcard nodeB: CCNode!) {

        var energy: CGFloat = pair.totalKineticEnergy

        // Kill seal if high impact
        if (energy > 5000) {
            _physicsNode!.space.addPostStepBlock({
                self.sealRemoved(nodeA)
            }, key:nodeA)
        }


    }

    // Seal Action
    func sealRemoved(seal: CCNode) {

        // Setup Particle
        var explosion: CCParticleSystem = CCBReader.load("SealExplosion") as CCParticleSystem

        explosion.autoRemoveOnFinish = true;

        explosion.position = seal.position;

        seal.parent.addChild(explosion);

        seal.removeFromParent()
    }

    func nextAttempt() {
        _currentPenguin = nil;
        _contentNode!.stopAction(_followPenguin);

        var actionMoveTo: CCAction = CCActionMoveTo.actionWithDuration(1, position:ccp(0, 0)) as CCAction;
        _contentNode!.runAction(actionMoveTo);
    }

    // Update
    override func update(delta: CCTime) {

        if (_currentPenguin?.launched == true) {

            // If speed below threshold then assume attempt over
            if Float(ccpLength(_currentPenguin!.physicsBody.velocity)) < MIN_SPEED {
                self.nextAttempt();
                return;
            }

            let xMin = _currentPenguin!.boundingBox().origin.x;

            if (xMin < self.boundingBox().origin.x) {
                self.nextAttempt();
                return;
            }

            let xMax = xMin + _currentPenguin!.boundingBox().size.width;

            if (xMax > (self.boundingBox().origin.x + self.boundingBox().size.width)) {
                self.nextAttempt();
                return;
            }
        }
    }

    // Menu
    func retry() {

        var gameplayScene: CCScene = CCBReader.loadAsScene("Gameplay")
        CCDirector.sharedDirector().replaceScene(gameplayScene);
    }


}