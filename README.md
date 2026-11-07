# jexi

一个 iOS 上的小工具：选一张（或一批）照片，一键把它的 EXIF 信息换成**这台设备上真实可读的数据**——机型、
系统版本、时间与时区、定位，以及按机型匹配的镜头与曝光参数。结果另存为新照片，原图不动。

界面用 Objective-C + UIKit 写成，没有 Swift，也没有第三方依赖。

## 功能

- **设备信息**：`sysctl` 读取 `hw.machine` / `kern.osversion`，机型表映射到市场名（如 iPhone 15 Pro）和该机型主摄参数。
- **时间**：`现在` 或 `指定` 某个日期时间，写入时带本地时区偏移（`+08:00`）。
- **定位**：`当前定位`，或 `附近随机`——在当前位置周边按 100 m / 500 m / 1 km / 5 km 的范围内随机取一个点（可关掉自定义范围，固定 500 m）。
- **批量**：一次选多张，同批共用同一个位置，逐张写出并保存，状态栏显示进度。
- **输出格式**：原格式 / JPEG / HEIF（换格式会重新编码，质量 0.95）。
- **超清增强**：Core Image 的 Lanczos 放大（2×/3×/4×）+ Unsharp Mask 锐化，长边上限 8192 像素，超过时自动降倍数。
- **文件名**：可开关的自定义命名，留空则 `IMG_` + 图片 SHA-256 的前 8 位。
- 写入时清空说明类字段（TIFF ImageDescription、EXIF UserComment、IPTC Caption/Headline/ObjectName）。
- **多选预览**：左右滑动查看，长按可删除当前这张。
- 关闭「真实定位」时，会把原照片里的 GPS 信息一并抹掉。

## 构建

本项目原本在 [Apelin](https://github.com/owngoal-dev/Apelin)（越狱设备上的 IDE）里创建，是一个 workspace 项目：

```sh
# 设备上通过 Apelin：
apelin_project_build     # 运行 apelin/build.sh，产出 .deb
apelin_package_install   # 安装到 /Applications/jexi.app
```

`apelin/build.sh` 会用 clang 编译全部 `Sources/*.m`、`ldid` 签名（`apelin/App.entitlements`）、
`dpkg-deb` 打包。不依赖 Theos。

在 macOS 上手动构建，等价于：

```sh
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
clang -arch arm64e -O2 -fobjc-arc -miphoneos-version-min=16.0 -ISources Sources/*.m \
  -o jexi -framework UIKit -framework Foundation -framework PhotosUI -framework Photos \
  -framework ImageIO -framework CoreLocation -framework CoreGraphics -framework UniformTypeIdentifiers
```

然后按 `Resources/Info.plist` 组装 `.app`，把 `Resources/Icon-*.png` 以 `Icon-60@2x` 等标准名拷进包内。

自测（不需要界面，验证 EXIF 写入、清 GPS、JPEG→HEIF 等）：

```sh
clang -arch arm64e -O1 -fobjc-arc -miphoneos-version-min=16.0 -ISources \
  Tools/metadata_test.m Sources/EXMetadata.m Sources/EXDevice.m -o metadata_test \
  -framework UIKit -framework Foundation -framework ImageIO -framework CoreLocation -framework CoreGraphics
ldid -STool.entitlements metadata_test && ./metadata_test
```

## 图标

`Tools/makeicon.m` 用 CoreGraphics + CoreText 直接画图标（渐变底 + 光圈环 + 字标），输出 120/152/167/180/1024 五档 PNG。

## 实现上踩过的坑

- `CGImageDestinationAddImageFromSource` 是**合并**语义：不传某个键不会删掉源里的值，传空字典也没用。
- 清除 GPS 要用 `CGImageDestinationCopyImageSource` + `kCGImageMetadataShouldExcludeGPS`；
  HEIF 上这个选项不生效，得解码后按属性重编码。
- `kCGImagePropertyGPSTimeStamp` 写成数组会让整个 GPS 块写坏，所以只写 `GPSDateStamp`。
- 设备上 HEIC 编码需要签名带 IOKit 用户客户端类（见 `apelin/App.entitlements`），否则 `Finalize` 静默失败。

## 目录

```
Sources/                 App 与 EXIF 读写逻辑
  EXRootViewController   界面、批量流程、定位与时间选项
  EXMetadata             ImageIO 读写 TIFF/EXIF/GPS
  EXDevice               sysctl 读设备信息 + 机型表
Resources/               Info.plist 与图标
Tools/                   自测程序与图标生成器
apelin/                  构建脚本与签名权限
```

## 免责声明

这个工具会修改照片的元数据（相机型号、时间、位置）。请只用于你自己的照片和你自己的用途；
拿它把别人的照片伪装成别处拍摄的，或用虚假信息误导他人，都不是这个项目的目的。

## 许可

见 LICENSE。
