# Melon — jexi（EXIF 编辑 App）

工作区项目，不是 Apelin 的模板工程：`apelin-project.json` 里声明了 `external.script = apelin/build.sh`，
`apelin_project_build` 会运行它，脚本用 `clang`（设备上的 Command Line Tools 15.3 + iOS SDK）编译
Objective-C App，`ldid -S` 签名，再用 `dpkg-deb` 打出唯一的 `.deb`。没有 Theos、没有 Swift 工具链。

显示名 `jexi`，可执行文件仍是 `ExifOne`，Bundle ID `com.melon.exifone`（装了就别改，改就是另一个 App）。
图标由 `Tools/makeicon.m` 生成（`Icon-120/152/167/180/1024.png` 放在 `Resources/`），
build.sh 以 `Icon-60@2x` 等标准文件名拷进 .app，Info.plist 用 `CFBundleIconFiles` 声明。
换图标：改 makeicon.m 后重新编译运行（用法见下），再 build/install。

## 构建与安装

```
apelin_project_build            # 运行 apelin/build.sh，产出 .deb
apelin_package_install          # 用 build 给的 artifact id / digest 安装
```

- 安装位置：`$APELIN_PREFIX/Applications/ExifOne.app`（roothide 的 `/Applications`），装完出现在主屏。
- Bundle ID / 包名：`com.melon.exifone`，版本在 `apelin/build.sh` 的 `VERSION` 里。
- 改 App 图标：放 `Resources/` 后由 build.sh 拷进 .app（目前没有图标）。

## 源码

- `Sources/main.m`、`Sources/EXAppDelegate.*`：入口，单一 `UINavigationController`，无 storyboard。
- `Sources/EXRootViewController.*`：全部界面（程序化 UIKit），选图用 `PHPickerViewController`（可多选），
  写回相册只有一种方式：另存新照片（见下）。
- `Sources/EXMetadata.*`：ImageIO 读写 EXIF/TIFF/GPS。`EXWriteOptions` 决定写设备信息、时间、定位。
- `Sources/EXDevice.*`：`sysctl` 读 `hw.machine` / `kern.osversion`，机型表映射到市场名与主摄参数。

## 保存方式

只有一种：**另存新照片**（`PHAssetCreationRequest` 新建资产）。相册里会显示“来自 EXIF 一键修改”，
这是系统记录的资产来源，**不是 EXIF 字段，App 内无法去掉**。原图始终不动。

- 曾经做过 `PHContentEditingInput` → `PHContentEditingOutput` 就地覆盖（为了不留来源标记），
  用户要求去掉，代码已删除。若要恢复：`adjustmentData` 给 nil 会报 PHPhotosErrorDomain 3303
  （Asset resource missing），必须给有效的 `PHAdjustmentData`。
- 批量：一次选多张（`PHPickerConfiguration.selectionLimit = 0`），后台队列逐张写临时文件，
  再 `PHAssetCreationRequest` 逐张保存，状态栏显示进度；同批共用同一个定位，时间各自生成。

## 时间与位置

- 时间模式只有 `现在` / `指定`（`UIDatePicker`），批量时所有照片共用同一个时间。
  时间浮动（随机范围）已按用户要求删除，`UIPickerView` 相关代码不要再加回来。
- 位置来源：当前定位 / 附近随机。只有切到“附近随机”才出现「自定义随机范围」开关（默认开）：
  关 = 固定 500 米内随机，开 = 显示 100 m / 500 m / 1 km / 5 km。取点在该范围的 15%–100% 内，
  球面公式，不联网；“换一个”重选，选好后“将要写入的真实设备数据”卡片里的位置立刻更新。
- 多选预览：`previewCard` 上挂左右 `UISwipeGestureRecognizer` 翻页（`UIPageControl` 指示），
  长按弹 `UIAlertController` 删除当前这张，删除后自动调整张数与预览。
- 日志：`os_log` subsystem `com.melon.exifone`、category `edit`。


## ImageIO 上踩过的坑（改代码前先看）

- `CGImageDestinationAddImageFromSource` 以源照片属性为底稿**合并**：不传某个键并不会删掉源里的值，
  传空字典也没用。要抹掉 GPS 必须换写法（见下）。
- `kCGImagePropertyGPSTimeStamp` 写成数组会让整个 GPS 块写坏（DateStamp 和坐标一起丢）。现在是
  只写 `GPSDateStamp`（UTC 日期）+ 坐标/海拔/精度/速度/方向，不写 TimeStamp。要加 TimeStamp 先自己验证。
- 清除 GPS 分两步试：先 `CopyImageSource` + `kCGImageMetadataShouldExcludeGPS`（JPEG 上无损、有效），
  读回确认真的没了；HEIF 上这个选项**不生效**，于是退回“解码成 CGImage 再按属性重编码”的兜底。
- **HEIC 编码需要 `apelin/App.entitlements` 里的两组 IOKit 用户客户端类**。没有它们，`public.heic`
  的 destination 建得出来、`Finalize` 却失败（探针里 A/B 两种写法都是 ok=0）；签名后立即可用。
  所以 build.sh 用 `ldid -S.../apelin/App.entitlements` 签名，不要改回 `ldid -S`。
- 同格式输出用 `AddImageFromSource` 原样拷贝压缩数据；`format:` 参数不同时才重新编码（质量 0.95）。


## 自测（不经过界面）

`Tools/metadata_test.m` 是命令行程序，生成测试图 → 写入 → 读回断言，覆盖机型/时间/时区/坐标/曝光参数/
尺寸保留/清除 GPS/JPEG→HEIF 转换/HEIF 上清除 GPS。目前 22 项全过：

```
clang -arch arm64e -O1 -fobjc-arc -miphoneos-version-min=16.0 -ISources \
  Tools/metadata_test.m Sources/EXMetadata.m Sources/EXDevice.m -o buildtmp/metadata_test \
  -framework UIKit -framework Foundation -framework ImageIO -framework CoreLocation -framework CoreGraphics
cd buildtmp && ldid -STool.entitlements metadata_test && ./metadata_test
```

`buildtmp/Tool.entitlements` 是自测程序签名用的（`platform-application` + no-sandbox），
否则 shell_run 会以 exit 137 杀掉它。整个 `buildtmp/` 不入库。

## 图标

```
clang -arch arm64e -O1 -fobjc-arc -miphoneos-version-min=16.0 Tools/makeicon.m \
  -o buildtmp/makeicon -framework Foundation -framework ImageIO -framework CoreGraphics -framework CoreText
cd buildtmp && ldid -STool.entitlements makeicon && ./makeicon ../Resources
```

纯 CoreGraphics + CoreText 画图（渐变底 + 光圈环 + "jexi" 字标），不依赖 UIKit。

