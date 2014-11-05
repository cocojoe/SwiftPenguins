import Foundation

class MainScene: CCNode {
    
    func play() {
        var gameplayScene: CCScene = CCBReader.loadAsScene("Gameplay")
        CCDirector.sharedDirector().replaceScene(gameplayScene);
    }
    
}
