# NipaPlay Windows 安装程序图片配置说明

## 图片文件列表

安装程序使用了以下图片文件来提供丰富的视觉体验：

### 1. 主要图片

- **`nipaplay_icon.ico`** (256x256)
  - 用途：窗口图标和程序图标
  - 来源：从 `icon.png` 自动转换生成

- **`installer_banner.bmp`** (497x373)
  - 用途：安装程序的欢迎页面和完成页面的大海报
  - 位置：显示在页面左侧
  - 来源：从 `assets/images/main_image.png` 裁剪和优化生成

- **`installer_small.bmp`** (164x314)  
  - 用途：其他安装页面顶部的小横幅图片
  - 位置：显示在页面右上角
  - 来源：从 `assets/images/main_image.png` 裁剪和优化生成

### 2. 卸载程序图片

- **`uninstaller_banner.bmp`** (497x373)
  - 用途：卸载程序的欢迎页面和完成页面的大海报
  - 位置：显示在页面左侧
  - 来源：当前与安装程序海报相同，可以独立定制

### 3. 可选扩展图片

- **`license_bg.bmp`** (400x300)
  - 用途：许可协议页面的背景图片（模糊效果）
  - 来源：从主图片模糊处理生成

- **`components_header.bmp`** (164x314)
- **`directory_header.bmp`** (164x314)  
- **`instfiles_header.bmp`** (164x314)
  - 用途：为不同页面提供独立的头部图片（当前与主横幅相同）
  - 可扩展：可以为每个页面定制不同的头部图片

## 页面配图展示

### 安装程序页面

1. **欢迎页面**：显示大海报 (`installer_banner.bmp`)
2. **许可协议页面**：显示小横幅 (`installer_small.bmp`)  
3. **组件选择页面**：显示小横幅 (`installer_small.bmp`)
4. **安装目录页面**：显示小横幅 (`installer_small.bmp`)
5. **安装进度页面**：显示小横幅 (`installer_small.bmp`)
6. **完成页面**：显示大海报 (`installer_banner.bmp`)

### 卸载程序页面

1. **卸载欢迎页面**：显示卸载海报 (`uninstaller_banner.bmp`)
2. **卸载确认页面**：显示小横幅 (`installer_small.bmp`)
3. **卸载进度页面**：显示小横幅 (`installer_small.bmp`)  
4. **卸载完成页面**：显示卸载海报 (`uninstaller_banner.bmp`)

## 图片处理效果

生成的图片经过以下处理优化：

- **锐化处理**：提升图像清晰度
- **亮度调节**：增强视觉效果 (105% 亮度)
- **饱和度提升**：增强色彩表现 (110% 饱和度)
- **对比度优化**：保持原始对比度 (100%)
- **无损压缩**：确保在安装程序中的最佳显示质量

## 自定义海报

如果需要自定义安装程序海报：

1. 替换 `assets/images/main_image.png` 为你的海报图片
2. 确保图片分辨率足够高（建议至少 1200x900）
3. GitHub Actions 会自动处理和生成所有所需的图片格式
4. 安装程序编译时会自动包含这些图片

## 技术细节

- 图片格式：BMP（Windows 安装程序标准格式）
- 颜色深度：24位真彩色
- 压缩：无压缩（确保兼容性）
- 编码：适配 NSIS 安装程序要求

通过这些配置，NipaPlay 的 Windows 安装程序提供了专业级的视觉体验，包含多层次的海报展示。 