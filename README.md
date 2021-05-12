# INFO2055 - Embedded Systems Project

This repository contains everything related to the Embedded Systems Project made by Antoine Malherbe, Chloé Preud'homme, Jérôme Bayaux and Tom Piron.

Please read [CHANGE URL](/Reports/Rapport_3_Projet_Embedded.pdf) in /Reports folder to get all details about the project (e.g software and hardware architecture choices, sensors choices, explanations about flash memory and bluetooth modules, etc.).

## Project Goal

_TO BE DONE_

## Table of content

* _Reports_
  * folder containing all reports
* _Schema_
  * folder containing all electronic schematics
* _Datasheets_
  * folder containing all datasheets of the components used
* _Conversion.pdf_ TODO
  * document explaining the different conversion formulas for the various sensors
* _.X folders_ (different MPLABX projects)
  * **_final.X_ : final code used on the PIC16 for the mushroom weather station**
  * _flash-test.X_ : project used to perform various tests with the flash memory module
  * _mushroom_with_flash.X_ : project containing code for weather station with flash memory module (_WORK IN PROGRESS_)
  * _store-in-ram.X_ : project that stores measurements in PIC16's linear memory (no bluetooth module)
  * _test-bluetooth.X_ : project used to perform various tests with the bluetooth module

## General Remarks

### Storage capacity
Here are the different possible options to store the measurements alongside with the maximum consecutive time during which the station can collect some data before it needs to send it via its Bluetooth module and some additional information.

### Storage capacity
Here are the different possible options to store the measurements alongside with the maximum consecutive time during which the station can collect some data before it needs to send it via its Bluetooth module and some additional information.

> **Note : See section 6 of [CHANGE URL](/Reports/Rapport_3_Projet_Embedded.pdf) about Memory Management to have more information.**

Type of storage                                   | Time before out of space (with measures every 15min) | How to implement ?                                          | Best Advantage
------------------------------------------------- | ---------------------------------------------------- | ----------------------------------------------------------- | --------------
2 bytes per measure in PIC16 (**_Current setup_**)| 4 days and 4 hours                                   | _Currently implemented_                                     | Most accurate method without flash
1 byte per measure in PIC16                       | 8 days and 8 hours                                   | Remove line ? to ? in [CHANGE URL](/final.X/without_flash.s)| Best space optimised
2 bytes per measure in Flash module               | several years                                        | Fix code of [mushroom.s](/mushroom_with_flash.X/mushroom.s) | Lot of space available

### Next Steps
1. Add some sensors
    1. More accurate and precised _luminosity sensor_
    2. _Gas sensor_
2. Add _timestamps_ to the measurements
3. Built _Mobile application_ to get data from the weather station without the bluetooth app used for testing

### Bluetooth App for testing
[Serial Bluetooth Terminal](https://play.google.com/store/apps/details?id=de.kai_morich.serial_bluetooth_terminal&hl=fr&gl=US)
