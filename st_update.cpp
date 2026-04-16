#include <Arduino.h>
#include <Adafruit_SSD1306.h>

#define OLED_Address 0x3C
Adafruit_SSD1306 oled(128, 64);

// 参数定义
#define ST_THRESHOLD 0.15     // ST段报警阈值（根据模拟量缩放调整）
#define SAMPLE_RATE 200       // 采样频率约为 200Hz
#define BUFFER_SIZE 128

// 状态变量
float ecgBuffer[BUFFER_SIZE];
int ecgIndex = 0;
float baseline = 0.5;        // 动态基线
unsigned long lastAlertTime = 0;

void setup() {
  oled.begin(SSD1306_SWITCHCAPVCC, OLED_Address);
  oled.clearDisplay();
  pinMode(A0, INPUT);
  pinMode(8, OUTPUT); // 报警蜂鸣器引脚
  Serial.begin(115200);
}

// 简单的实时峰值提取与ST监测算法
void analyzeSTSegment(float currentVal) {
  static float lastVal = 0;
  static float rPeak = 0;
  static int samplesAfterR = 0;
  static bool trackingST = false;

  // 1. 简单的斜率检测查找R波 (QRS检测)
  float slope = currentVal - lastVal;
  if (slope > 0.08 && currentVal > 0.7) { // 识别到上升沿
    rPeak = currentVal;
    samplesAfterR = 0;
    trackingST = true;
  }

  // 2. 识别到R波后，延迟约 60ms-80ms (约 12-16 个采样点) 测量ST段
  if (trackingST) {
    samplesAfterR++;
    if (samplesAfterR == 15) { // 此时大致处于ST段位置
      float stLevel = currentVal; 
      float stShift = stLevel - baseline; // 计算相对于基线的偏移

      // 3. 预警逻辑
      if (abs(stShift) > ST_THRESHOLD) {
        triggerAlert(stShift);
      }
      trackingST = false; 
    }
  }

  // 4. 动态更新基线 (简单的一阶低通滤波)
  baseline = baseline * 0.99 + currentVal * 0.01;
  lastVal = currentVal;
}

void triggerAlert(float shift) {
  if (millis() - lastAlertTime > 2000) { // 避免频繁报警
    oled.setCursor(0, 0);
    oled.setTextColor(WHITE);
    if (shift > 0) oled.print("ST Elevation!");
    else oled.print("ST Depression!");
    
    digitalWrite(8, HIGH); // 触发蜂鸣器
    delay(100);
    digitalWrite(8, LOW);
    lastAlertTime = millis();
  }
}

void loop() {
  int rawValue = analogRead(A0);
  float normalizedVal = rawValue / 1024.0;

  // 存储到缓存用于绘图
  ecgBuffer[ecgIndex] = normalizedVal;
  ecgIndex = (ecgIndex + 1) % BUFFER_SIZE;

  // 实时算法分析
  analyzeSTSegment(normalizedVal);

  // 每5个点刷新一次显示，节省CPU资源供算法运行
  static int drawCount = 0;
  if (drawCount++ > 5) {
    oled.clearDisplay();
    // 绘制基线参考线
    oled.drawLine(0, 32, 127, 32, SSD1306_WHITE);
    
    // 绘制心电波形
    for (int i = 1; i < BUFFER_SIZE; i++) {
      int prev = (ecgIndex + i - 1) % BUFFER_SIZE;
      int curr = (ecgIndex + i) % BUFFER_SIZE;
      oled.drawLine(i-1, 64 - ecgBuffer[prev]*64, i, 64 - ecgBuffer[curr]*64, WHITE);
    }
    oled.display();
    drawCount = 0;
  }

  delay(5); // 约200Hz采样
}