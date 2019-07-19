//
//  RotationWithPenPedalPlugin.swift
//  ARPen
//
//  Created by Donna Klamma on 22.05.19.
//  Copyright © 2019 RWTH Aachen. All rights reserved.
//

import Foundation
import ARKit

class RotationWithPenPedalPlugin: Plugin,UserStudyRecordPluginProtocol {
    var recordManager: UserStudyRecordManager!
    var pluginImage: UIImage? = UIImage.init(named: "ObjectCreationPlugin")
    var pluginIdentifier: String = "Rotation with pen: Pedal"
    var currentView : ARSCNView?
    var currentScene : PenScene?
    
    var startPenOrientation = simd_quatf()
    var startBoxToPenOrientation = simd_quatf()
    var startBoxOrientation = simd_quatf()
    var updatedBoxToPenOrientation = simd_quatf()
    var updatedPenOrientation = simd_quatf()
    var quaternionFromStartToUpdatedBoxToPenOrientation = simd_quatf()
    var quaternionFromStartToUpdatedPenOrientation = simd_quatf()
    
    var updatesSincePressed = 0
    var selected : Bool = false
    var firstSelection : Bool = false

    var rotationAxis = simd_float3()
    var angle : Float = 0.0

    //Variables For USER STUDY TASK
    var randomAngle : Float = 0.0
    var randomAxis = simd_float3()
    var randomOrientation = simd_quatf()
    
    var ModelToRotatedBoxOrientation = simd_quatf()
    var originialBoxOrientation = simd_quatf()
    //variables for measuring
    var selectionCounter = 0
    var angleBetweenBoxAndModel : Float = 0.0
    var angleBetweenBoxAndModelEnd : Float = 0.0
    var degreesBoxWasRotated : Float = 0.0
    var degreesPenWasRotated: Float = 0.0
    
    var startTime : Date = Date()
    var endTime : Date = Date()
    var elapsedTime: Double = 0.0
    
    var userStudyReps = 0
    
    var studyData : [String:String] = [:]
    
    var rotationTime: Float = 0
    
    func didUpdateFrame(scene: PenScene, buttons: [Button: Bool]){
        guard let scene = self.currentScene else {return}
        guard let box = scene.drawingNode.childNode(withName: "currentBoxNode", recursively: false) else{
            print("box not found")
            return
        }
        guard let model = scene.drawingNode.childNode(withName: "modelBoxNode", recursively: false) else{
            print("model not found")
            return
        }
        guard let sceneView = self.currentView else { return }
        let checked = buttons[Button.checkButton]!
        let undo = buttons[Button.undoButton]!
        
        let pressed = buttons[Button.Button1]!
        if pressed{
            //"activate" box while buttons is pressed and select it therefore
            //project point onto image plane and see if geometry is behind it via hittest
            let projectedPenTip = CGPoint(x: Double(sceneView.projectPoint(scene.pencilPoint.position).x), y: Double(sceneView.projectPoint(scene.pencilPoint.position).y))
            var hitResults = sceneView.hitTest(projectedPenTip, options: [SCNHitTestOption.searchMode : SCNHitTestSearchMode.all.rawValue] )
            if hitResults.first?.node == model{
                hitResults.removeFirst()
            }
            if hitResults.first?.node == scene.pencilPoint{
                hitResults.removeFirst()
            }
            if let boxHit = hitResults.first?.node{
                if selected == false{
                    selected = true
                    
                    //boxHit.geometry?.firstMaterial?.diffuse.contents = UIColor.green
                    //this is a workaround to only highlight the body as we know the object that is hit
                    box.childNode(withName: "Body", recursively: true)?.geometry?.firstMaterial?.diffuse.contents = UIColor.green
                    
                    selectionCounter = selectionCounter + 1
                    if selectionCounter == 1{
                        startTime = Date()
                        degreesPenWasRotated = 0.0
                    }
                    firstSelection = true
                }
            }
            
            //if just pressed, initialize PenOrientation
            //initial box orientation is used for all calculations between box and (later updated) pen orientation
            if updatesSincePressed == 0 {
                startPenOrientation = scene.pencilPoint.simdOrientation
                startBoxOrientation = box.simdOrientation
                startBoxToPenOrientation = startPenOrientation * simd_inverse(startBoxOrientation)
            }
            updatesSincePressed += 1
            
            updatedPenOrientation = scene.pencilPoint.simdOrientation
            updatedBoxToPenOrientation = updatedPenOrientation * simd_inverse(startBoxOrientation)
            //calculate rotation that would keep angle/orientation between original box orientation to pen the same at all points in time
            quaternionFromStartToUpdatedBoxToPenOrientation = updatedBoxToPenOrientation * simd_inverse(startBoxToPenOrientation)
            
            //for documentation
            quaternionFromStartToUpdatedPenOrientation = updatedPenOrientation * simd_inverse(startPenOrientation)
            quaternionFromStartToUpdatedPenOrientation = quaternionFromStartToUpdatedPenOrientation.normalized
            degreesPenWasRotated = degreesPenWasRotated + abs(quaternionFromStartToUpdatedPenOrientation.angle.radiansToDegrees)
            startPenOrientation = updatedPenOrientation
            
            //get rotation axis between original box and updated pen orientation and convert it to world space to use for rotation on box
            rotationAxis = quaternionFromStartToUpdatedBoxToPenOrientation.axis
            rotationAxis = box.simdConvertVector(rotationAxis, from: nil)
            
            angle = quaternionFromStartToUpdatedBoxToPenOrientation.angle
            
            //determine the speed of rotation, the more the pen is angled in a certain direction the faster the box rotates in that direction
            var rotation = simd_quatf()
            if (angle >= Float(0.0).degreesToRadians && angle < Float(3.0).degreesToRadians || angle <= Float(360.0).degreesToRadians && angle > Float(357.0).degreesToRadians){
                rotation = simd_quatf(angle: Float(0.0).degreesToRadians, axis: rotationAxis)
            }
            else if (angle >= Float(3.0).degreesToRadians && angle < Float(20.0).degreesToRadians || angle <= Float(357.0).degreesToRadians && angle > Float(340.0).degreesToRadians){
                rotation = simd_quatf(angle: Float(0.5).degreesToRadians, axis: rotationAxis)
            }
            else if (angle >= Float(20.0).degreesToRadians && angle < Float(80.0).degreesToRadians || angle <= Float(340.0).degreesToRadians && angle > Float(280.0).degreesToRadians){
                rotation = simd_quatf(angle: Float(1.0).degreesToRadians, axis: rotationAxis)
            }
            else if (angle >= Float(80.0).degreesToRadians && angle < Float(180.0).degreesToRadians || angle <= Float(280.0).degreesToRadians && angle > Float(180.0).degreesToRadians){
                rotation = simd_quatf(angle: Float(3.0).degreesToRadians, axis: rotationAxis)
            }
            
            if selected == true && rotation.angle.radiansToDegrees < 20.0{
                rotation = rotation.normalized
                box.simdLocalRotate(by: rotation)
                degreesBoxWasRotated = degreesBoxWasRotated + rotation.angle.radiansToDegrees
                //degreesPenWasRotated = degreesPenWasRotated + abs(quaternionFromStartToUpdatedPenOrientation.angle.radiansToDegrees)
            }
        }
        else{
            selected = false
            
            box.childNode(withName: "Body", recursively: true)?.geometry?.firstMaterial?.diffuse.contents = UIColor.red
            updatesSincePressed = 0
            
            //if task is ended at this point the left amount of degrees between the objects is recorded
            ModelToRotatedBoxOrientation = box.simdOrientation * simd_inverse(model.simdOrientation)
            if(ModelToRotatedBoxOrientation.angle.radiansToDegrees <= 180.0){
                angleBetweenBoxAndModelEnd = ModelToRotatedBoxOrientation.angle.radiansToDegrees
            }
            else{
                angleBetweenBoxAndModelEnd = 360.0 - ModelToRotatedBoxOrientation.angle.radiansToDegrees
            }
            
            //in case task is ended at this point record endTime
            endTime = Date()
        }
        
        //user study task
        if checked == true && firstSelection == true && selected == false {
            elapsedTime = endTime.timeIntervalSince(startTime)
            
            studyData.updateValue(String(selectionCounter), forKey: "Number of Selections in attempt " + String(userStudyReps))
            studyData.updateValue(String(degreesBoxWasRotated), forKey: "Degrees Object was rotated in attempt " + String(userStudyReps))
            studyData.updateValue(String(angleBetweenBoxAndModel), forKey: "The starting angle between Box and Model in attempt " + String(userStudyReps))
            studyData.updateValue(String(degreesPenWasRotated), forKey: "Degrees pen was rotated in attempt " + String(userStudyReps))
            studyData.updateValue(String(elapsedTime), forKey: "Elapsed time in attempt: " + String(userStudyReps))
            studyData.updateValue(String(angleBetweenBoxAndModelEnd), forKey: "The angle between Box and Model at the end in attempt " + String(userStudyReps))
            
            print("userStudyReps: ", userStudyReps)
            print("selection counter: ", selectionCounter)
            print("degrees box was rotated :", degreesBoxWasRotated)
            print("angle between box and model: ", angleBetweenBoxAndModel)
            print("angle between box and model end: ", angleBetweenBoxAndModelEnd)
            print("degreesPenWasRotated: ", degreesPenWasRotated)
            print("time: ", elapsedTime)
            
            //create random orientation for model
            randomAngle = Float.random(in: 0...360).degreesToRadians
            randomAxis = simd_float3(x: Float.random(in: -1...1), y: Float.random(in: -1...1), z: Float.random(in: -1...1))
            randomOrientation = simd_quatf(angle: randomAngle, axis: randomAxis)
            randomOrientation = randomOrientation.normalized
            
            //new random orientation for model
            model.simdLocalRotate(by: randomOrientation)
            //reset box Orientation
            box.simdOrientation = originialBoxOrientation
            
            //measurement variables
            selectionCounter = 0
            degreesBoxWasRotated = 0.0
            //degreesPenWasRotated = 0.0
            
            ModelToRotatedBoxOrientation = box.simdOrientation * simd_inverse(model.simdOrientation)
            if(ModelToRotatedBoxOrientation.angle.radiansToDegrees <= 180.0){
                angleBetweenBoxAndModel = ModelToRotatedBoxOrientation.angle.radiansToDegrees
            }
            else{
                angleBetweenBoxAndModel = 360.0 - ModelToRotatedBoxOrientation.angle.radiansToDegrees
            }
            
            selected = false
            firstSelection = false
            
            box.childNode(withName: "Body", recursively: true)?.geometry?.firstMaterial?.diffuse.contents = UIColor.red
            
            userStudyReps += 1
        }
        
        //make objects disappear after six reps
        if userStudyReps == 6{
            box.removeFromParentNode()
            model.removeFromParentNode()
            
            recordManager.addNewRecord(withIdentifier: "Pen Pedal Rotation", andData: studyData)
        }
        
        //in the case a mistake was made undo to re-do attempt
        if undo == true{
            box.childNode(withName: "Body", recursively: true)?.geometry?.firstMaterial?.diffuse.contents = UIColor.red
            
            elapsedTime = 0.0
            selectionCounter = 0
            degreesPenWasRotated = 0.0
            degreesBoxWasRotated = 0.0
            firstSelection = false
            selected = false
            
            //create random orientation for model
            randomAngle = Float.random(in: 0...360).degreesToRadians
            randomAxis = simd_float3(x: Float.random(in: -1...1), y: Float.random(in: -1...1), z: Float.random(in: -1...1))
            randomOrientation = simd_quatf(angle: randomAngle, axis: randomAxis)
            randomOrientation = randomOrientation.normalized
            
            //new random orientation for model
            model.simdLocalRotate(by: randomOrientation)
            //reset box Orientation
            box.simdOrientation = originialBoxOrientation
            
            ModelToRotatedBoxOrientation = box.simdOrientation * simd_inverse(model.simdOrientation)
            if(ModelToRotatedBoxOrientation.angle.radiansToDegrees <= 180.0){
                angleBetweenBoxAndModel = ModelToRotatedBoxOrientation.angle.radiansToDegrees
            }
            else{
                angleBetweenBoxAndModel = 360.0 - ModelToRotatedBoxOrientation.angle.radiansToDegrees
            }
            
        }
    }
    
    func activatePlugin(withScene scene: PenScene, andView view: ARSCNView) {
        self.currentScene = scene
        self.currentView = view
        
        if recordManager.currentActiveUserID == nil{
            recordManager.currentActiveUserID = -1
        }
        
        let ship = SCNScene(named: "art.scnassets/arkit-rocket.dae")
        let rocketNode = ship?.rootNode.childNode(withName: "Rocket", recursively: true)
        rocketNode?.scale = SCNVector3Make(0.3, 0.3, 0.3)
        let rocketNodeModel = rocketNode?.clone()
        
        let boxNode = rocketNode!
        //create Object to rotate
        if boxNode != scene.drawingNode.childNode(withName: "currentBoxNode", recursively: false){
            //boxNode.geometry = rocketNode?.geometry
            boxNode.position = SCNVector3(0, 0, -0.5)
            //boxNode.geometry?.materials = [white, blue, red, cyan, orange, purple]
            boxNode.name = "currentBoxNode"
            boxNode.opacity = 0.9
            
            scene.drawingNode.addChildNode(boxNode)
        }
        else{
            boxNode.position = SCNVector3(0, 0, -0.5)
        }
        originialBoxOrientation = boxNode.simdOrientation
        
        //create random orientation for model
        randomAngle = Float.random(in: 0...360).degreesToRadians
        randomAxis = simd_float3(x: Float.random(in: -1...1), y: Float.random(in: -1...1), z: Float.random(in: -1...1))
        randomOrientation = simd_quatf(angle: Float(randomAngle), axis: randomAxis)
        randomOrientation = randomOrientation.normalized
        
        //create Object as model
        var boxModel = rocketNodeModel!
        if boxModel != scene.drawingNode.childNode(withName: "modelBoxNode", recursively: false){
            boxModel.position = SCNVector3(0, 0, -0.5)
            boxModel.name = "modelBoxNode"
            boxModel.opacity = 0.5
            
            boxModel.simdLocalRotate(by: randomOrientation)
            scene.drawingNode.addChildNode(boxModel)
        }
        else{
            boxModel.position = SCNVector3(0, 0, -0.5)
        }
        
        ModelToRotatedBoxOrientation = boxNode.simdOrientation * simd_inverse(boxModel.simdOrientation)
        if(ModelToRotatedBoxOrientation.angle.radiansToDegrees <= 180.0){
            angleBetweenBoxAndModel = ModelToRotatedBoxOrientation.angle.radiansToDegrees
        }
        else{
            angleBetweenBoxAndModel = 360.0 - ModelToRotatedBoxOrientation.angle.radiansToDegrees
        }
    }
    
    func deactivatePlugin() {
        if let box = currentScene?.drawingNode.childNode(withName: "currentBoxNode", recursively: false){
            box.removeFromParentNode()
        }
        
        if let modelBox = currentScene?.drawingNode.childNode(withName: "modelBoxNode", recursively: false){
            modelBox.removeFromParentNode()
        }
        
        self.currentScene = nil
        self.currentView = nil
    }
    
}
