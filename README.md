# INFO2055 - Embedded Systems Project

This repository contains everything related to the Embedded Systems Project made by Antoine Malherbe, Chloé Preud'homme, Jérôme Bayaux and Tom Piron.

Please read [Final Report](/Reports/Rapport_Final.pdf) in /Reports folder to get all details about the project (e.g software and hardware architecture choices, sensors choices, explanations about flash memory and bluetooth modules, etc.).

## Project Goal

The objectives of this project consist in measuring and collecting data about the environment in a mushroom box. This mushroom box is an idea of the Pot’Ingé, a group of students and PhD students building a vegetable garden at the University of Liège willing to harvest mushrooms in a mushroom box. To help them monitor their mushroom culture, several environment variables such as temperature, air humidity, light level and CO<sub>2</sub> concentration should be measured with sensors and should be easily accessible for the user. The idea was to store the measurements in an external flash memory module until a user requests them. When this happens, the data will be sent through a Bluetooth module.

Our priority was focused on making sure that the temperature, humidity and light sensor function properly. We planned to add the gas measurements only if there was some time left once all the other sensors as well as the Bluetooth module work correctly. Indeed, it is more interesting to have a complete working cycle (i.e data acquisition, storage and sending) than to have a gas sensor that was considered as an added value to our project since it is more difficult to handle and quite expensive.

## Table of content

* _Reports_
  * folder containing all reports
* _Schematics_
  * folder containing all electronic schematics
* _Datasheets_
  * folder containing all datasheets of the components used
* _Conversion.pdf_
  * document explaining the different conversion formulas for the various sensors
* _.X folders_ (different MPLABX projects)
  * **_final.X_ : final code used on the PIC16 for the mushroom weather station**
  * _flash-test.X_ : project used to perform various tests with the flash memory module
  * _mushroom_with_flash.X_ : project containing code for weather station with flash memory module (_WORK IN PROGRESS_)
  * _store-in-ram.X_ : project that stores measurements in PIC16's linear memory (no bluetooth module)
  * _test-bluetooth.X_ : project used to perform various tests with the bluetooth module

## General Remarks

### Storage Capacity
Here are the different possible options to store the measurements alongside with the maximum consecutive time during which the station can collect some data before it needs to send it via its Bluetooth module and some additional information.

> **Note : See section 6 of [Final Report](/Reports/Rapport_Final.pdf) about Memory Management to have more information.**

Type of storage                                   | Time before out of space (with measures every 15min) | How to implement ?                                          | Best Advantage
------------------------------------------------- | ---------------------------------------------------- | ----------------------------------------------------------- | --------------
2 bytes per measure in PIC16 (**_Current setup_**)| 4 days and 4 hours                                   | _Currently implemented_                                     | Most accurate method without Flash Module
1 byte per measure in PIC16                       | 8 days and 8 hours                                   | Remove line 239 and 240 in [main.s](/final.X/main.s)| Best space optimised
2 bytes per measure in Flash module               | several years                                        | Fix code of [mushroom.s](/mushroom_with_flash.X/mushroom.s) | Lot of space available

### Next Steps
1. Add some sensors
    1. More accurate and precised _luminosity sensor_
    2. _Gas sensor_
2. Add _timestamps_ to the measurements
3. Built _Mobile application_ to get data from the weather station without the bluetooth app used for testing

### Bluetooth App for testing
[Serial Bluetooth Terminal](https://play.google.com/store/apps/details?id=de.kai_morich.serial_bluetooth_terminal&hl=fr&gl=US)
