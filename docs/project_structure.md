# 项目目录结构

本文档用于说明本项目的推荐目录规划。当前阶段先创建目录和占位文件，后续每个功能分支再逐步补充具体代码、脚本、模型和调试记录。

## 总体结构

```text
TAISHANPAI_3M/
├── app/
│   ├── camera/
│   ├── common/
│   ├── display/
│   ├── face/
│   └── service/
├── config/
├── data/
│   └── faces/
├── docs/
├── models/
├── scripts/
├── systemd/
└── README.md
```

## 目录说明

| 路径 | 作用 |
| --- | --- |
| `app/` | 应用层源码根目录，后续放 C/C++ 主程序和各业务模块。 |
| `app/camera/` | 摄像头采集模块，计划封装 V4L2 或 OpenCV 采集逻辑。 |
| `app/display/` | 屏幕显示模块，计划封装预览画面、识别框和状态显示逻辑。 |
| `app/face/` | 人脸检测、特征提取、人脸比对和人员库相关逻辑。 |
| `app/service/` | 配置、日志、识别记录、systemd 辅助逻辑等工程化模块。 |
| `app/common/` | 通用工具，例如线程安全队列、时间工具、错误码定义等。 |
| `config/` | 运行配置文件，例如摄像头设备、分辨率、识别阈值和数据路径。 |
| `models/` | 人脸检测和识别模型文件。模型通常较大，后续可用下载说明替代直接提交。 |
| `data/` | 运行数据目录，例如识别记录数据库、临时文件等。 |
| `data/faces/` | 本地人员图片或特征数据目录。 |
| `scripts/` | 构建、启动、部署和调试脚本。 |
| `systemd/` | systemd service 文件，用于开机自启动和异常重启。 |
| `docs/` | 项目规划、技术路线、调试记录、开发日志和简历整理文档。 |

## 后续代码规划

后续进入实现阶段时，建议逐步补充以下文件：

```text
app/
├── main.cpp
├── camera/
│   ├── v4l2_camera.cpp
│   └── v4l2_camera.h
├── display/
│   ├── display.cpp
│   └── display.h
├── face/
│   ├── face_detector.cpp
│   ├── face_recognizer.cpp
│   └── face_database.cpp
├── service/
│   ├── config.cpp
│   ├── logger.cpp
│   └── record.cpp
└── common/
    └── thread_queue.h
```

建议不要一开始就把所有文件写满。每个分支只补当前阶段需要的模块，保证每次提交都有明确目标和可验证结果。
