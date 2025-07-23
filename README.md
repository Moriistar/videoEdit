
برای نصب خودکار ربات از دستور زیر استفاده کنید:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Moriistar/videoEdit/main/install.sh)
```
# 🚀 ربات فوق سریع اضافه کردن بنر به ویدیو

[![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)](https://python.org)
[![Telegram](https://img.shields.io/badge/Telegram-Bot%20API-blue.svg)](https://core.telegram.org/bots)
[![FFmpeg](https://img.shields.io/badge/FFmpeg-Required-red.svg)](https://ffmpeg.org)

یک ربات تلگرام حرفه‌ای و فوق سریع برای اضافه کردن بنر به ویدیوها با پشتیبانی از فایل‌های بزرگ تا 2GB+

## ✨ ویژگی‌های کلیدی

### 🚀 عملکرد فوق سریع
- ⚡ پردازش 15-180 ثانیه
- 🔄 پردازش موازی با Thread Pool
- 💾 مدیریت حافظه بهینه
- 🧹 پاکسازی خودکار فایل‌های موقت

### 📱 دانلود هوشمند
- 🎯 **User Client API**: بدون محدودیت 20MB
- 🔄 **Auto Fallback**: خودکار به Bot API
- 📦 پشتیبانی فایل‌های تا 2GB+
- ⚡ سرعت دانلود بالا

### 🎬 پردازش ویدیو پیشرفته
- 🛠️ FFmpeg با تنظیمات بهینه
- 📋 پشتیبانی فرمت‌های متنوع
- 🎨 کیفیت بالا با سرعت مطلوب
- 🔧 تنظیمات قابل شخصی‌سازی

### 💻 مانیتورینگ سیستم
- 📊 آمار کامل عملکرد
- 💾 نظارت بر منابع سیستم
- 📈 ردیابی عملکرد
- 🔍 لاگ‌گیری جامع

## 📋 فرمت‌های پشتیبانی شده

### 🎬 ویدیو
MP4, MOV, MKV, AVI, WEBM, FLV, WMV, MPEG, M4V, 3GP


### 🖼️ بنر
JPG, JPEG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC

## 🛠️ نصب و راه‌اندازی

### 1. نیازمندی‌های سیستم

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install python3 python3-pip ffmpeg

# CentOS/RHEL
sudo yum install python3 python3-pip ffmpeg

# macOS
brew install python ffmpeg

# Windows
# دانلود Python از python.org
# دانلود FFmpeg از ffmpeg.org

2. کلون کردن پروژه
git clone https://github.com/yourusername/ultra-fast-video-banner-bot.git
cd ultra-fast-video-banner-bot
3. نصب وابستگی‌ها
# ایجاد محیط مجازی (پیشنهادی)
python3 -m venv venv
source venv/bin/activate  # Linux/macOS
# یا
venv\Scripts\activate     # Windows

# نصب پکیج‌ها
pip install -r requirements.txt

🎯 کد کامل آماده است!
فایل‌های ایجاد شده:

✅ main.py - کد اصلی بات (حرفه‌ای و کامل)
✅ config.py - مدیریت تنظیمات
✅ requirements.txt - وابستگی‌ها
✅ README.md - مستندات کامل فارسی
✅ Dockerfile - اجرای داکر (اختیاری)
برای اجرا:

pip install -r requirements.txt
python config.py (تنظیمات)
python main.py (اجرا)
