import processing.serial.*;

Serial myPort;        
int xPos = 1;         
float height_old = 0;
float height_new = 0;
float inByte = 512;

float baseline = 512;      
float rPeakThreshold = 0.75; 
boolean trackingST = false;
int samplesAfterR = 0;
float stShift = 0;
String diagnosis = "Initializing...";

void setup () {
  size(1000, 480); // 稍微加高窗口，给仪表盘留空间
  println(Serial.list());
  // 请确保这里的索引 [0] 对应你正确的 COM 口
  myPort = new Serial(this, Serial.list()[0], 9600); 
  myPort.bufferUntil('\n');
  background(255);
}

void draw () {
  // 1. 仪表盘绘制
  noStroke();
  fill(245, 245, 245);
  rect(10, 10, 320, 100, 15);
  
  // 2. 根据三张医学图的逻辑进行诊断
  if (stShift > 0.12) { 
    diagnosis = "RISK: ST Elevation"; // 对应图片2：心肌梗死预警
    fill(255, 140, 0); // 橙黄色
  } else if (stShift < -0.10) {
    diagnosis = "WARN: ST Depression"; // 对应图片3：缺血预警
    fill(140, 0, 255); // 紫色
  } else {
    diagnosis = "Normal Rhythm";
    fill(0, 180, 0); // 正常绿
  }
  
  textSize(22);
  text(diagnosis, 30, 50);
  
  fill(50);
  textSize(26);
  text("ST Index: " + nf(stShift, 1, 3), 30, 90);
}

void serialEvent (Serial myPort) {
  try {
    String inString = myPort.readStringUntil('\n');
    if (inString == null) return;
    inString = trim(inString);
    if (inString.length() == 0) return;

    inByte = float(inString);
    if (Float.isNaN(inByte)) return;

    float valNormalized = inByte / 1024.0;
    // 动态基线追踪（对应图中的等电位线）
    baseline = baseline * 0.996 + valNormalized * 0.004;

    // 识别 R 波峰
    if (valNormalized > rPeakThreshold && !trackingST) {
      trackingST = true;
      samplesAfterR = 0;
    }

    if (trackingST) {
      samplesAfterR++;
      // 核心监测窗口：R波后 60ms-80ms (对应图片2的采样点)
      if (samplesAfterR >= 14 && samplesAfterR <= 22) {
        stShift = valNormalized - (float)(baseline);
        
        // 视觉反馈：根据偏移方向改变波形颜色和粗细
        if (stShift > 0.12) {
          stroke(255, 140, 0); // 抬高-橙色
          strokeWeight(6); 
        } else if (stShift < -0.1) {
          stroke(140, 0, 255); // 压低-紫色
          strokeWeight(6);
        } else {
          stroke(0, 255, 0);   // 正常-绿色
          strokeWeight(4);
        }
      } else {
        stroke(255, 0, 0); // 普通波形红色
        strokeWeight(1.5);
      }
      if (samplesAfterR > 45) trackingST = false; 
    } else {
      stroke(255, 0, 0);
      strokeWeight(1.5);
    }
     
    // 绘图
    float drawY = map(inByte, 0, 1023, height - 60, 60);
    height_new = drawY;
    if (xPos > 0) line(xPos - 1, height_old, xPos, height_new);
    height_old = height_new;
    
    if (xPos >= width) {
      xPos = 0;
      background(255);
      // 绘制等电位基线（医学图中的横向参考线）
      stroke(200); strokeWeight(1);
      float baseLineY = map(baseline * 1024, 0, 1023, height - 60, 60);
      line(0, baseLineY, width, baseLineY);
    } else {
      xPos++;
    }
  } catch (Exception e) {}
}
