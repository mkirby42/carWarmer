#include <ArduinoBLE.h>
#include <Arduino_HTS221.h>  // Library for onboard humidity/temperature sensor
#include <Adafruit_MAX31856.h> // Library for thermocouple amplifier

// Define SPI pins for MAX31856
#define CS 10
#define MOSI 11
#define MISO 12
#define SCK 13

// Define battery pin
#define BAT A0

// Initialize MAX31856 object
Adafruit_MAX31856 maxthermo = Adafruit_MAX31856(CS, MOSI, MISO, SCK);

// BLE Service and Characteristics
BLEService sensorService("180A");  // Custom BLE service

BLEFloatCharacteristic tempCharacteristic("2A6E", BLERead | BLENotify);   // Temperature from thermocouple
// BLEFloatCharacteristic humidityCharacteristic("2A6F", BLERead | BLENotify); // Humidity from onboard sensor
BLEFloatCharacteristic batteryCharacteristic("2A19", BLERead | BLENotify);  // Battery voltage

void setup() {
  Serial.begin(115200);
  while (!Serial) delay(10);

  maxthermo.begin();
  maxthermo.setThermocoupleType(MAX31856_TCTYPE_B);

  // Initialize the onboard humidity sensor
  // if (!HTS.begin()) {
  //   Serial.println("Failed to initialize HTS221 sensor.");
  //   while (1);
  // }

  // Initialize BLE
  if (!BLE.begin()) {
    Serial.println("Failed to initialize BLE.");
    while (1);
  }

  BLE.setLocalName("Nano33BLE_Sensor");  // BLE device name
  BLE.setAdvertisedService(sensorService);  // Set the advertised service

  // Add the characteristics to the service
  sensorService.addCharacteristic(tempCharacteristic);
  // sensorService.addCharacteristic(humidityCharacteristic);
  sensorService.addCharacteristic(batteryCharacteristic);

  BLE.addService(sensorService);
  BLE.advertise();

  Serial.println("BLE device is now advertising.");
}

void loop() {
  // Wait for a BLE central to connect
  BLEDevice central = BLE.central();
  if (central) {
    Serial.print("Connected to central: ");
    Serial.println(central.address());

    while (central.connected()) {
      // Read data from sensors
      float thermocoupleTemp = readThermocoupleTemperature();
      // float humidity = readHumidity();
      float batteryLevel = readBatteryVoltage();

      // Update BLE characteristics
      tempCharacteristic.writeValue(thermocoupleTemp);
      // humidityCharacteristic.writeValue(humidity);
      batteryCharacteristic.writeValue(batteryLevel);

      // Print values to Serial (optional)
      Serial.print("Thermocouple Temp: ");
      Serial.print(thermocoupleTemp);
      // Serial.print(" °C, Humidity: ");
      // Serial.print(humidity);
      Serial.print(" %, Battery: ");
      Serial.print(batteryLevel);
      Serial.println(" V");

      delay(1000);  // Update every second
    }

    Serial.println("Disconnected from central.");
  }
}

// Function to read temperature from the thermocouple
float readThermocoupleTemperature() {
  uint8_t fault = maxthermo.readFault();
  if (fault) {
    if (fault & MAX31856_FAULT_CJRANGE) Serial.println("Cold Junction Range Fault");
    if (fault & MAX31856_FAULT_TCRANGE) Serial.println("Thermocouple Range Fault");
    if (fault & MAX31856_FAULT_CJHIGH)  Serial.println("Cold Junction High Fault");
    if (fault & MAX31856_FAULT_CJLOW)   Serial.println("Cold Junction Low Fault");
    if (fault & MAX31856_FAULT_TCHIGH)  Serial.println("Thermocouple High Fault");
    if (fault & MAX31856_FAULT_TCLOW)   Serial.println("Thermocouple Low Fault");
    if (fault & MAX31856_FAULT_OVUV)    Serial.println("Over/Under Voltage Fault");
    if (fault & MAX31856_FAULT_OPEN)    Serial.println("Thermocouple Open Fault");
  }
  return maxthermo.readThermocoupleTemperature();
}

// Function to read humidity from the onboard HTS221 sensor
float readHumidity() {
  return HTS.readHumidity();  // Directly reading the humidity
}

// Function to read battery voltage using a voltage divider on A0
float readBatteryVoltage() {
  int raw = analogRead(BAT);
  float voltage = raw * (3.3 / 1023.0) * 2;  // Adjust for voltage divider
  return voltage;
}