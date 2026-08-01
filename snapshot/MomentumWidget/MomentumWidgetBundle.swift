//
//  MomentumWidgetBundle.swift
//  MomentumWidget
//
//  Created by Aidan O'Brien on 24/07/2025.
//

import WidgetKit
 import SwiftUI

 @main
 struct MomentumWidgetBundle: WidgetBundle {
     var body: some Widget {
         // Any existing widgets here
         MomentumWidget() // (if you have a regular widget)

         // Add the Live Activity
         if #available(iOS 16.2, *) {
             RoutineLiveActivity()
         }
     }
 }
