package com.example.riderlink

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Template

class MainCarScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        return MessageTemplate.Builder("RiderLink Active")
            .setTitle("Status: Monitoring")
            .build()
    }
}
