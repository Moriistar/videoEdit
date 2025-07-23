# 🎬 Telegram Video Banner Bot

یک ربات تلگرام قدرتمند برای اضافه کردن بنر به ویدیوها با کیفیت بالا و سرعت پردازش عالی.

## ✨ ویژگی‌های اصلی

- 🎯 **اضافه کردن بنر تمام صفحه** به ویدیوها
- ⏱️ **نمایش بنر در ثانیه اول** ویدیو
- 📱 **رابط کاربری ساده** و مرحله به مرحله
- 🔧 **حفظ کیفیت اصلی** ویدیو
- ⚡ **پردازش سریع** با FFmpeg
- 🗂️ **مدیریت حافظه بهینه** و پاک‌سازی خودکار
- 📊 **کنترل حجم فایل** (حداکثر 2TB)

## 🚀 نصب سریع

برای نصب خودکار ربات از دستور زیر استفاده کنید:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Moriistar/videoEdit/main/install.sh)
```

## 📋 پیش‌نیازها

- **Python 3.8+**
- **FFmpeg** (برای پردازش ویدیو)
- **python-telegram-bot** library
- **Bot Token** از BotFather

### نصب دستی پیش‌نیازها:

#### Ubuntu/Debian:
```bash
sudo apt update
sudo apt install python3 python3-pip ffmpeg -y
pip3 install python-telegram-bot
```

#### CentOS/RHEL:
```bash
sudo yum install python3 python3-pip ffmpeg -y
pip3 install python-telegram-bot
```

#### macOS:
```bash
brew install python3 ffmpeg
pip3 install python-telegram-bot
```

## 🔧 راه‌اندازی

### 1. دریافت Bot Token
1. به [@BotFather](https://t.me/botfather) در تلگرام پیام دهید
2. دستور `/newbot` را ارسال کنید
3. نام و username برای ربات انتخاب کنید
4. Token دریافتی را کپی کنید

### 2. اجرای ربات
```bash
python3 video_banner_bot.py
```

### 3. وارد کردن اطلاعات
- **Bot Token**: توکن دریافتی از BotFather
- **Owner ID**: شناسه عددی تلگرام شما ([دریافت ID](https://t.me/userinfobot))

## 📖 نحوه استفاده

### برای کاربران:

1. **شروع**: `/start` را در ربات ارسال کنید
2. **ارسال بنر**: عکس بنر مورد نظر را ارسال کنید
3. **ارسال ویدیو**: ویدیو مورد نظر را ارسال کنید
4. **دریافت نتیجه**: ویدیو با بنر آماده را دریافت کنید


## 🛠️ پیکربندی پیشرفته

### تنظیمات FFmpeg
```python
# در فایل کد، می‌توانید تنظیمات زیر را تغییر دهید:
'-preset', 'fast',    # سرعت پردازش: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
'-crf', '23',         # کیفیت: 0-51 (کمتر = بهتر، 23 توصیه می‌شود)
```

### تغییر موقعیت و زمان بنر
```python
# تغییر فیلتر FFmpeg برای شخصی‌سازی:
'[1:v]scale=iw:ih[banner];[0:v][banner]overlay=0:0:enable=\'between(t,0,1)\'[out]'
# overlay=0:0 = موقعیت (X,Y)
# between(t,0,1) = زمان نمایش (از ثانیه 0 تا 1)
```

## 🔍 عیب‌یابی

### مشکلات رایج:

#### خطای FFmpeg:
```bash
# بررسی نصب FFmpeg
ffmpeg -version

# نصب مجدد در Ubuntu
sudo apt install ffmpeg --reinstall
```

#### خطای Python Dependencies:
```bash
# نصب مجدد کتابخانه
pip3 install --upgrade python-telegram-bot

# بررسی نسخه Python
python3 --version
```

#### خطای دسترسی:
```bash
# اعطای مجوز اجرا
chmod +x video_banner_bot.py
```

## 📊 نظارت و لاگ‌ها

ربات تمام فعالیت‌ها را در کنسول نمایش می‌دهد:

```bash
# اجرا با نمایش جزئیات بیشتر
python3 video_banner_bot.py 2>&1 | tee bot.log
```

## 🔐 امنیت

- 🔒 **محافظت از Token**: هرگز Token خود را عمومی نکنید
- 🗂️ **پاک‌سازی خودکار**: فایل‌های موقت به صورت خودکار حذف می‌شوند
- 👤 **کنترل کاربر**: تنها کاربران مجاز می‌توانند استفاده کنند

## 🆕 به‌روزرسانی

```bash
# دانلود آخرین نسخه
curl -O https://raw.githubusercontent.com/Moriistar/videoEdit/main/video_banner_bot.py

# اجرای مجدد
python3 video_banner_bot.py
```

## 🤝 مشارکت

برای مشارکت در توسعه:

1. Repository را Fork کنید
2. تغییرات خود را اعمال کنید
3. Pull Request ارسال کنید

## 📞 پشتیبانی

- 🐛 **گزارش باگ**: در Issues گیت‌هاب
- 💡 **پیشنهادات**: در Discussions
- 📧 **تماس مستقیم**: [اطلاعات تماس]

## 📄 مجوز

این پروژه تحت مجوز MIT منتشر شده است.

---

**ساخته شده با ❤️ برای جامعه ایرانی**

### 🌟 حمایت از پروژه

اگر این ربات برایتان مفید بود، لطفاً:
- ⭐ Star بدهید
- 🔄 Share کنید
- 🐛 باگ‌ها را گزارش دهید

---

**نکته**: این ربات برای استفاده شخصی و تجاری رایگان است. در صورت استفاده تجاری، لطفاً منبع را ذکر کنید.
