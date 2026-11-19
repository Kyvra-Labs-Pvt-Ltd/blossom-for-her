#pragma once
// ======================================
// KYVRA CUSTOM PCB - PIN CONFIGURATION
// ======================================
// N8R8 reminder: never use GPIO 35, 36, 37 (octal PSRAM).

// LED GPIOs
#define LED_GREEN  40
#define LED_WHITE  41
#define LED_RED    42
#define LED_BLUE   47
#define LED_ACTIVE_HIGH 1   // 1: GPIO high = LED on.  0: GPIO low = LED on.

// Camera data pins
#define CAM_D0     11
#define CAM_D1     9
#define CAM_D2     8
#define CAM_D3     10
#define CAM_D4     12
#define CAM_D5     18
#define CAM_D6     17
#define CAM_D7     16

// Camera control pins
#define CAM_XCLK   15
#define CAM_PCLK   13
#define CAM_VSYNC  6
#define CAM_HREF   7

// Camera SCCB (I2C)
#define CAM_SDA    4
#define CAM_SCL    5

// Camera power/reset
#define CAM_PWDN   -1
#define CAM_RESET  -1
