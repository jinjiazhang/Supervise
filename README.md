# 小小练习场

支持 iOS 16 及以上的 iPhone。竖直固定手机，打开语音提醒，选择本组目标。双脚放平站稳约一秒，听到“开始”后再做动作。

- **跳绳**　面向前置摄像头，全身和双脚入镜。按双脚起落计数，每十次报数。绳子是否成功过脚需要人工确认。
- **踮脚**　侧身站立，选能看清近侧脚跟和前脚掌的角度。脚跟抬起并放下后报数，停留在高处算同一个动作。
- 两种练习到达目标都会结束并提醒休息。暂停、切到后台或短时离开画面时保留本组次数，结束后可返回首页开始新的一组。
- 摄像头画面只用于本机推理。目标次数和语音开关保存在本机，画面不录像、不上传。

## 运行

当前工作区已装好依赖。用 Xcode 打开 `Supervise.xcworkspace`，选择 Supervise 和已配对的 iPhone 后运行。首次启动练习时允许访问摄像头。

在新检出目录中，先用 CocoaPods 执行 `pod install`。使用其他开发者账号时，在 Supervise target 的 Signing & Capabilities 中选择自己的 Team 和可用的 Bundle Identifier。若通过 XcodeGen 修改工程结构，编辑 `project.yml` 后执行 `xcodegen generate` 和 `pod install`。

## 识别与验证

前置摄像头采集竖屏视频，由随 App 打包的 [MediaPipe Pose Landmarker Lite](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker) 提取关键点。跳绳模式综合双侧前脚掌和髋部的升降，踮脚模式跟踪同一侧脚跟相对前脚掌的高度。阈值随画面中的腿长缩放，关键点暂时丢失会丢弃尚未完成的动作。

运行合成关键点序列回归检查：

```sh
swiftc App/MotionCounter.swift Checks/main.swift -o /tmp/check-supervise-motion
/tmp/check-supervise-motion
```

真机试数时可由家长独立数一组跳绳和一组踮脚，再分别比较。将持续踮起、单脚迈步和中途离开画面穿插在两组之间，可检查额外计数。
