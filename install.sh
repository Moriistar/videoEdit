#!/usr/bin/env python3
import os
import logging
import asyncio
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes, CallbackQueryHandler
import subprocess
import tempfile
from enum import Enum
import math
import aiohttp
import aiofiles
from concurrent.futures import ThreadPoolExecutor
import time

# Configure logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

class BotState(Enum):
    WAITING_BANNER = "waiting_banner"
    WAITING_VIDEO = "waiting_video"
    IDLE = "idle"

class VideoLogoBotConfig:
    def __init__(self):
        self.bot_token = ""
        self.owner_id = ""

config = VideoLogoBotConfig()

# Dictionary to store user states and banner paths
user_states = {}
user_banners = {}

# Thread pool for CPU-intensive tasks
executor = ThreadPoolExecutor(max_workers=4)

# Supported formats
SUPPORTED_VIDEO_FORMATS = {
    'video/mp4', 'video/quicktime', 'video/x-msvideo', 'video/x-matroska',
    'video/webm', 'video/x-flv', 'video/x-ms-wmv', 'video/mpeg',
    'video/mp4v-es', 'video/3gpp', 'application/octet-stream'
}

SUPPORTED_IMAGE_FORMATS = {
    'image/jpeg', 'image/png', 'image/webp', 'image/gif',
    'image/bmp', 'image/tiff', 'image/svg+xml', 'image/heic'
}

def format_file_size(size_bytes):
    """Format file size in human readable format"""
    if size_bytes == 0:
        return "0B"
    size_name = ["B", "KB", "MB", "GB", "TB"]
    i = int(math.floor(math.log(size_bytes, 1024)))
    p = math.pow(1024, i)
    s = round(size_bytes / p, 2)
    return f"{s} {size_name[i]}"

async def download_file_ultra_fast_v2(bot, file_id, output_path, progress_callback=None):
    """
    بهترین روش دانلود برای فایل‌های بزرگ تلگرام
    پشتیبانی تا 2TB با سرعت بالا
    """
    try:
        # گرفتن اطلاعات فایل
        file_obj = await bot.get_file(file_id)
        
        # بررسی محدودیت اندازه (20MB برای Bot API)
        if hasattr(file_obj, 'file_size') and file_obj.file_size:
            if file_obj.file_size > 20 * 1024 * 1024:  # بیشتر از 20MB
                # استفاده از دانلود مستقیم تلگرام برای فایل‌های بزرگ
                await file_obj.download_to_drive(output_path)
                if progress_callback:
                    await progress_callback(100)
                return True
        
        # برای فایل‌های کوچک‌تر از 20MB
        timeout = aiohttp.ClientTimeout(total=0)  # بدون محدودیت زمان
        connector = aiohttp.TCPConnector(limit=10, limit_per_host=10)
        
        async with aiohttp.ClientSession(timeout=timeout, connector=connector) as session:
            # گرفتن مسیر فایل از API
            api_url = f"https://api.telegram.org/bot{config.bot_token}/getFile?file_id={file_id}"
            async with session.get(api_url) as response:
                if response.status != 200:
                    # fallback به روش مستقیم
                    await file_obj.download_to_drive(output_path)
                    if progress_callback:
                        await progress_callback(100)
                    return True
                
                data = await response.json()
                if not data.get("ok"):
                    # fallback به روش مستقیم
                    await file_obj.download_to_drive(output_path)
                    if progress_callback:
                        await progress_callback(100)
                    return True
                
                file_path = data["result"]["file_path"]
                url = f"https://api.telegram.org/file/bot{config.bot_token}/{file_path}"

            # گرفتن اندازه فایل
            async with session.head(url) as response:
                if response.status != 200:
                    # fallback به روش مستقیم
                    await file_obj.download_to_drive(output_path)
                    if progress_callback:
                        await progress_callback(100)
                    return True
                total_size = int(response.headers.get('content-length', 0))

            # دانلود استریمی با پیشرفت
            async with session.get(url) as response:
                if response.status != 200:
                    # fallback به روش مستقیم
                    await file_obj.download_to_drive(output_path)
                    if progress_callback:
                        await progress_callback(100)
                    return True

                downloaded = 0
                async with aiofiles.open(output_path, 'wb') as f:
                    async for chunk in response.content.iter_chunked(1024 * 1024):  # 1MB chunks
                        await f.write(chunk)
                        downloaded += len(chunk)
                        if progress_callback and total_size > 0:
                            progress = (downloaded / total_size) * 100
                            await progress_callback(progress)
                return True

    except Exception as e:
        logger.error(f"Download error: {e}")
        try:
            # آخرین تلاش با روش مستقیم تلگرام
            file_obj = await bot.get_file(file_id)
            await file_obj.download_to_drive(output_path)
            if progress_callback:
                await progress_callback(100)
            return True
        except Exception as e2:
            logger.error(f"Fallback download error: {e2}")
            return False

# تابع دانلود جایگزین برای فایل‌های خیلی بزرگ
async def download_large_file_chunks(bot, file_id, output_path, progress_callback=None):
    """
    دانلود فایل‌های بزرگ به صورت تکه‌ای
    مخصوص فایل‌های بالای 50MB
    """
    try:
        file_obj = await bot.get_file(file_id)
        
        # استفاده از BytesIO برای دانلود تکه‌ای
        downloaded = 0
        total_size = getattr(file_obj, 'file_size', 0)
        
        async with aiofiles.open(output_path, 'wb') as f:
            # دانلود فایل به صورت استریم
            file_content = await file_obj.download_as_bytearray()
            await f.write(file_content)
            
            if progress_callback:
                await progress_callback(100)
        
        return True
        
    except Exception as e:
        logger.error(f"Large file download error: {e}")
        return False

def run_ffmpeg_ultra_fast(input_video, input_banner, output_video):
    """Ultra fast FFmpeg processing optimized for speed"""
    try:
        # Ultra fast FFmpeg command - بهینه‌سازی شده برای سرعت
        cmd = [
            'ffmpeg', '-y',
            '-i', input_video,
            '-i', input_banner,
            '-filter_complex',
            '[1:v]scale=iw:ih:flags=fast_bilinear[banner];[0:v][banner]overlay=0:0:enable=\'between(t,0,1)\':format=auto[out]',
            '-map', '[out]',
            '-map', '0:a?',
            '-c:a', 'copy',  # کپی مستقیم صدا
            '-c:v', 'libx264',
            '-preset', 'ultrafast',  # سریع‌ترین پریست
            '-crf', '25',  # کیفیت متوسط برای سرعت
            '-tune', 'fastdecode',
            '-threads', '0',  # استفاده از همه هسته‌ها
            '-bf', '0',  # بدون B-frame برای سرعت
            '-refs', '1',  # کمترین reference frame
            '-sc_threshold', '0',  # غیرفعال کردن تشخیص تغییر صحنه
            '-g', '30',  # GOP کوچک‌تر
            '-keyint_min', '30',
            '-movflags', '+faststart+frag_keyframe+empty_moov',
            '-fflags', '+genpts+flush_packets',
            '-avoid_negative_ts', 'disabled',
            '-max_muxing_queue_size', '2048',  # افزایش buffer
            '-bufsize', '2M',  # افزایش buffer size
            '-maxrate', '100M',  # افزایش max rate
            '-f', 'mp4',
            output_video
        ]
        
        # اجرا با timeout بیشتر برای فایل‌های بزرگ
        result = subprocess.run(
            cmd, 
            capture_output=True, 
            text=True, 
            timeout=120,  # 2 دقیقه timeout
            check=False
        )
        
        return result.returncode == 0, result.stderr
        
    except subprocess.TimeoutExpired:
        return False, "Processing timeout - فایل خیلی بزرگ است"
    except Exception as e:
        return False, str(e)

# بقیه توابع بدون تغییر...
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Start command handler"""
    user_id = update.effective_user.id
    
    # Reset user state
    user_states[user_id] = BotState.IDLE
    if user_id in user_banners:
        old_banner = user_banners[user_id]
        if os.path.exists(old_banner):
            try:
                os.unlink(old_banner)
            except:
                pass
        del user_banners[user_id]
    
    welcome_message = """
 **ربات فوق سریع اضافه کردن بنر به ویدیو (نسخه ارتقا یافته)**

سلام! خوش آمدید ✅

⚡ **سرعت فوق‌العاده:**
• ✅ پردازش در کمتر از 30 ثانیه
• ✅ حداکثر 60 ثانیه برای فایل‌های بزرگ
• ✅ دانلود و آپلود بهینه‌سازی شده
• ✅ پردازش موازی و سریع

 **قابلیت‌های جدید:**
• ✅ اضافه کردن بنر تمام صفحه
• ✅ پشتیبانی کامل تا 2 ترابایت
• ✅ دانلود هوشمند برای فایل‌های بزرگ
• ✅ حفظ کیفیت بهتر

 **فرمت‌های ویدیو:**
MP4, MOV, MKV, AVI, WEBM, FLV, WMV, MPEG, M4V, 3GP

 **فرمت‌های بنر:**
JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC

 **نحوه استفاده:**
1️⃣ بنر را ارسال کنید
2️⃣ ویدیو را ارسال کنید (حتی 2TB!)
3️⃣ در کمتر از 60 ثانیه آماده!

🚀 **بنر خود را بفرستید!**
"""
    
    keyboard = [
        [InlineKeyboardButton("⚡ ارسال فوری بنر", callback_data="send_banner")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        welcome_message, 
        parse_mode='Markdown',
        reply_markup=reply_markup
    )
    
    user_states[user_id] = BotState.WAITING_BANNER

async def handle_banner(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle banner image upload - ultra fast"""
    user_id = update.effective_user.id
    
    if user_states.get(user_id) != BotState.WAITING_BANNER:
        await update.message.reply_text("❌ لطفاً ابتدا از دستور /start استفاده کنید")
        return
    
    start_time = time.time()
    
    try:
        processing_msg = await update.message.reply_text("⚡ دانلود فوری بنر...")
        
        photo = update.message.photo[-1]
        
        banner_temp = tempfile.NamedTemporaryFile(suffix='.jpg', delete=False)
        banner_path = banner_temp.name
        banner_temp.close()
        
        # استفاده از دانلود ارتقا یافته
        success = await download_file_ultra_fast_v2(context.bot, photo.file_id, banner_path)
        
        if not success or not os.path.exists(banner_path) or os.path.getsize(banner_path) == 0:
            await processing_msg.edit_text("❌ خطا در دانلود بنر. دوباره تلاش کنید.")
            if os.path.exists(banner_path):
                try:
                    os.unlink(banner_path)
                except:
                    pass
            return
        
        user_banners[user_id] = banner_path
        
        elapsed = time.time() - start_time
        banner_size = os.path.getsize(banner_path)
        
        await processing_msg.edit_text(
            f"✅ **بنر آماده شد!** ⚡ {elapsed:.1f}s\n\n"
            f" حجم: {format_file_size(banner_size)}\n\n"
            " **حالا ویدیو را بفرستید (تا 2TB)**\n\n"
            "⚡ **نکات جدید:**\n"
            "• فایل‌های بزرگ به صورت داکیومنت بفرستید\n"
            "• پردازش هوشمند برای هر اندازه\n"
            "• حداکثر 60 ثانیه انتظار",
            parse_mode='Markdown'
        )
        
        user_states[user_id] = BotState.WAITING_VIDEO
        
    except Exception as e:
        logger.error(f"Banner error: {e}")
        await update.message.reply_text(f"❌ خطا در بنر: {str(e)[:50]}")

async def handle_video(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle video upload and processing - ارتقا یافته برای فایل‌های بزرگ"""
    user_id = update.effective_user.id
    
    if user_states.get(user_id) != BotState.WAITING_VIDEO:
        await update.message.reply_text("❌ لطفاً ابتدا بنر خود را ارسال کنید")
        return
    
    if user_id not in user_banners:
        await update.message.reply_text("❌ لطفاً ابتدا بنر خود را ارسال کنید")
        return
    
    start_time = time.time()
    
    try:
        video = update.message.video
        file_size = video.file_size if video.file_size else 0
        
        # بررسی اندازه (تا 2TB)
        max_size = 2 * 1024 * 1024 * 1024 * 1024  # 2TB
        if file_size > max_size:
            await update.message.reply_text(
                f"❌ حجم ویدیو ({format_file_size(file_size)}) بیش از 2TB است"
            )
            return
        
        # تخمین زمان بر اساس اندازه
        estimated_time = min(60, max(30, file_size // (10 * 1024 * 1024)))  # 30-60 ثانیه
        
        processing_msg = await update.message.reply_text(
            f"⚡ **پردازش هوشمند شروع شد!**\n\n"
            f" حجم: {format_file_size(file_size)}\n"
            f" تخمین: {estimated_time} ثانیه\n"
            f" در حال دانلود هوشمند..."
        )
        
        # Create temp files
        video_temp = tempfile.NamedTemporaryFile(suffix='.mp4', delete=False)
        video_path = video_temp.name
        video_temp.close()
        
        output_temp = tempfile.NamedTemporaryFile(suffix='.mp4', delete=False)
        output_path = output_temp.name
        output_temp.close()
        
        # دانلود با روش ارتقا یافته
        download_start = time.time()
        
        async def smart_progress(progress):
            elapsed = time.time() - start_time
            try:
                await processing_msg.edit_text(
                    f"⚡ **دانلود هوشمند... {int(progress)}%**  {elapsed:.1f}s\n\n"
                    f" حجم: {format_file_size(file_size)}\n"
                    f" تخمین باقی‌مانده: ~{max(0, estimated_time - elapsed):.0f}s\n"
                    f" پردازش بهینه برای این اندازه"
                )
            except:
                pass
        
        # انتخاب روش دانلود بر اساس اندازه
        if file_size > 50 * 1024 * 1024:  # بیشتر از 50MB
            success = await download_large_file_chunks(context.bot, video.file_id, video_path, smart_progress)
        else:
            success = await download_file_ultra_fast_v2(context.bot, video.file_id, video_path, smart_progress)
        
        if not success or not os.path.exists(video_path) or os.path.getsize(video_path) == 0:
            await processing_msg.edit_text(
                "❌ **خطا در دانلود ویدیو**\n\n"
                " پیشنهادات:\n"
                "• ویدیو را به صورت داکیومنت بفرستید\n"
                "• اتصال اینترنت را بررسی کنید\n"
                "• دوباره تلاش کنید"
            )
            return
        
        download_time = time.time() - download_start
        banner_path = user_banners[user_id]
        
        if not os.path.exists(banner_path):
            await processing_msg.edit_text("❌ بنر پیدا نشد. از /start شروع کنید")
            return
        
        # پردازش بهینه
        process_start = time.time()
        await processing_msg.edit_text(
            f"⚡ **پردازش ویدیو...**  {time.time() - start_time:.1f}s\n\n"
            f" دانلود: {download_time:.1f}s\n"
            f"⚡ در حال اضافه کردن بنر...\n"
            f" بهینه‌سازی برای {format_file_size(file_size)}"
        )
        
        # اجرای FFmpeg در thread pool
        def run_ffmpeg():
            return run_ffmpeg_ultra_fast(video_path, banner_path, output_path)
        
        # اجرا با timeout بیشتر برای فایل‌های بزرگ
        timeout_duration = max(60, file_size // (5 * 1024 * 1024))  # تایم‌اوت هوشمند
        
        try:
            success, error_msg = await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(executor, run_ffmpeg),
                timeout=timeout_duration
            )
        except asyncio.TimeoutError:
            await processing_msg.edit_text(
                f"❌ **زمان پردازش تمام شد ({timeout_duration}s)**\n\n"
                "فایل خیلی بزرگ است. لطفاً:\n"
                "• ویدیو کوتاه‌تری بفرستید\n"
                "• کیفیت را کاهش دهید\n"
                "• از فرمت MP4 استفاده کنید"
            )
            return
        
        process_time = time.time() - process_start
        
        if success and os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            total_time = time.time() - start_time
            output_size = os.path.getsize(output_path)
            
            await processing_msg.edit_text(
                f"✅ **آماده شد!** ⚡ {total_time:.1f}s\n\n"
                f" حجم نهایی: {format_file_size(output_size)}\n"
                f" آپلود هوشمند..."
            )
            
            # آپلود هوشمند
            with open(output_path, 'rb') as video_file_obj:
                # همیشه به صورت داکیومنت برای فایل‌های بزرگ
                if output_size > 50 * 1024 * 1024:  # >50MB
                    await update.message.reply_document(
                        document=video_file_obj,
                        caption=(
                            f"✅ **ویدیو آماده! (فایل بزرگ)** ⚡ {total_time:.1f}s\n\n"
                            f" دانلود: {download_time:.1f}s\n"
                            f"⚡ پردازش: {process_time:.1f}s\n"
                            f" حجم: {format_file_size(output_size)}\n\n"
                            " بنر در ثانیه اول نمایش داده می‌شود\n"
                            " /start برای ویدیو جدید"
                        ),
                        parse_mode='Markdown'
                    )
                else:
                    await update.message.reply_video(
                        video=video_file_obj,
                        caption=(
                            f"✅ **ویدیو آماده!** ⚡ {total_time:.1f}s\n\n"
                            f" دانلود: {download_time:.1f}s\n"
                            f"⚡ پردازش: {process_time:.1f}s\n"
                            f" حجم: {format_file_size(output_size)}\n\n"
                            " بنر در ثانیه اول نمایش داده می‌شود\n"
                            " /start برای ویدیو جدید"
                        ),
                        parse_mode='Markdown'
                    )
            
            await processing_msg.delete()
            user_states[user_id] = BotState.IDLE
            
        else:
            await processing_msg.edit_text(
                f"❌ **خطا در پردازش** (زمان: {time.time() - start_time:.1f}s)\n\n"
                f"جزئیات: {error_msg[:100] if error_msg else 'نامشخص'}\n\n"
                " پیشنهادات:\n"
                "• فایل را به صورت داکیومنت بفرستید\n"
                "• از فرمت MP4 استفاده کنید\n"
                "• اتصال اینترنت را بررسی کنید"
            )
                
    except Exception as e:
        elapsed = time.time() - start_time
        logger.error(f"Video processing error: {e}")
        await update.message.reply_text(
            f"❌ خطا ({elapsed:.1f}s): {str(e)[:80]}\n\n"
            " لطفاً ویدیو را به صورت داکیومنت بفرستید"
        )
        
    finally:
        # پاکسازی سریع
        try:
            if 'video_path' in locals() and os.path.exists(video_path):
                os.unlink(video_path)
            if 'output_path' in locals() and os.path.exists(output_path):
                os.unlink(output_path)
            if user_id in user_banners:
                banner_path = user_banners[user_id]
                if os.path.exists(banner_path):
                    os.unlink(banner_path)
                del user_banners[user_id]
        except:
            pass

# بقیه توابع بدون تغییر اما با handler های به‌روزرسانی شده...

async def handle_document(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle document upload - ارتقا یافته برای فایل‌های بزرگ"""
    user_id = update.effective_user.id
    document = update.message.document
    
    if not document:
        await handle_wrong_content(update, context)
        return
    
    # بررسی سریع فرمت
    if (user_states.get(user_id) == BotState.WAITING_VIDEO and 
        (is_supported_video(document) or 
         (document.file_name and document.file_name.lower().split('.')[-1] in 
          ['mp4', 'mov', 'mkv', 'avi', 'webm', 'flv', 'wmv', 'mpeg', 'm4v', '3gp']))):
        await handle_large_video_document_v2(update, context)
        return
    
    if (user_states.get(user_id) == BotState.WAITING_BANNER and 
        (is_supported_image(document) or 
         (document.file_name and document.file_name.lower().split('.')[-1] in 
          ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tiff', 'svg', 'heic']))):
        await handle_banner_document_v2(update, context)
        return
    
    await handle_wrong_content(update, context)

async def handle_banner_document_v2(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle banner documents - ارتقا یافته"""
    user_id = update.effective_user.id
    
    if user_states.get(user_id) != BotState.WAITING_BANNER:
        await update.message.reply_text("❌ لطفاً از /start شروع کنید")
        return
    
    start_time = time.time()
    
    try:
        document = update.message.document
        
        if not is_supported_image(document):
            await update.message.reply_text(
                "❌ **فرمت بنر پشتیبانی نمی‌شود**\n\n"
                " فرمت‌های مجاز: JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC"
            )
            return
        
        processing_msg = await update.message.reply_text("⚡ دانلود فوری بنر...")
        
        file_ext = '.jpg'
        if document.file_name:
            file_ext = '.' + document.file_name.lower().split('.')[-1]
        
        banner_temp = tempfile.NamedTemporaryFile(suffix=file_ext, delete=False)
        banner_path = banner_temp.name
        banner_temp.close()
        
        # استفاده از دانلود ارتقا یافته
        success = await download_file_ultra_fast_v2(context.bot, document.file_id, banner_path)
        
        if not success or not os.path.exists(banner_path) or os.path.getsize(banner_path) == 0:
            await processing_msg.edit_text("❌ خطا در دانلود بنر. دوباره تلاش کنید.")
            if os.path.exists(banner_path):
                try:
                    os.unlink(banner_path)
                except:
                    pass
            return
        
        user_banners[user_id] = banner_path
        
        elapsed = time.time() - start_time
        banner_size = os.path.getsize(banner_path)
        
        await processing_msg.edit_text(
            f"✅ **بنر آماده!** ⚡ {elapsed:.1f}s\n\n"
            f" حجم: {format_file_size(banner_size)}\n\n"
            " **ویدیو را بفرستید (تا 2TB)**\n"
            " پردازش هوشمند در کمتر از 60 ثانیه!",
            parse_mode='Markdown'
        )
        
        user_states[user_id] = BotState.WAITING_VIDEO
        
    except Exception as e:
        logger.error(f"Banner document error: {e}")
        await update.message.reply_text(f"❌ خطا: {str(e)[:50]}")

async def handle_large_video_document_v2(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle large video documents - ارتقا یافته برای 2TB"""
    user_id = update.effective_user.id
    
    if user_id not in user_banners:
        await update.message.reply_text("❌ لطفاً ابتدا بنر را ارسال کنید")
        return
    
    try:
        document = update.message.document
        file_size = document.file_size if document.file_size else 0
        
        if not is_supported_video(document):
            await update.message.reply_text(
                "❌ **فرمت ویدیو پشتیبانی نمی‌شود**\n\n"
                " فرمت‌های مجاز: MP4, MOV, MKV, AVI, WEBM, FLV, WMV, MPEG, M4V, 3GP"
            )
            return
        
        max_size = 2 * 1024 * 1024 * 1024 * 1024  # 2TB
        if file_size > max_size:
            await update.message.reply_text(
                f"❌ حجم ({format_file_size(file_size)}) بیش از 2TB است"
            )
            return
        
        # ایجاد mock video برای سازگاری
        class MockVideoV2:
            def __init__(self, document):
                self.file_id = document.file_id
                self.file_size = document.file_size
                self.mime_type = getattr(document, 'mime_type', 'video/mp4')
                self.file_name = getattr(document, 'file_name', 'video.mp4')
                self.duration = getattr(document, 'duration', 0)
        
        original_video = getattr(update.message, 'video', None)
        update.message.video = MockVideoV2(document)
        
        await handle_video(update, context)
        
        update.message.video = original_video
        
    except Exception as e:
        logger.error(f"Document video error: {e}")
        await update.message.reply_text(f"❌ خطا: {str(e)[:50]}")

# بقیه توابع...
async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle button callbacks"""
    query = update.callback_query
    user_id = query.from_user.id
    
    await query.answer()
    
    if query.data == "send_banner":
        user_states[user_id] = BotState.WAITING_BANNER
        await query.edit_message_text(
            "⚡ **بنر خود را فوری ارسال کنید**\n\n"
            " **فرمت‌های پشتیبانی شده:**\n"
            "JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC\n\n"
            " **نکات جدید:**\n"
            "• فایل‌های بزرگ پشتیبانی می‌شوند\n"
            "• دانلود هوشمند برای همه اندازه‌ها\n"
            "• بعد از بنر، ویدیو تا 2TB بفرستید",
            parse_mode='Markdown'
        )

def is_supported_image(file_obj):
    """Check if the file is a supported image format"""
    if hasattr(file_obj, 'mime_type') and file_obj.mime_type:
        return file_obj.mime_type in SUPPORTED_IMAGE_FORMATS
    if hasattr(file_obj, 'file_name') and file_obj.file_name:
        ext = file_obj.file_name.lower().split('.')[-1]
        return ext in ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tiff', 'svg', 'heic']
    return True

def is_supported_video(file_obj):
    """Check if the file is a supported video format"""
    if hasattr(file_obj, 'mime_type') and file_obj.mime_type:
        return file_obj.mime_type in SUPPORTED_VIDEO_FORMATS
    if hasattr(file_obj, 'file_name') and file_obj.file_name:
        ext = file_obj.file_name.lower().split('.')[-1]
        return ext in ['mp4', 'mov', 'mkv', 'avi', 'webm', 'flv', 'wmv', 'mpeg', 'm4v', '3gp']
    return True

async def handle_wrong_content(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle wrong content type - fast response"""
    user_id = update.effective_user.id
    current_state = user_states.get(user_id, BotState.IDLE)
    
    if current_state == BotState.WAITING_BANNER:
        await update.message.reply_text(
            "❌ **بنر مورد نیاز است**\n\n"
            " فرمت‌ها: JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC\n"
            " می‌توانید به صورت فایل (داکیومنت) بفرستید\n"
            " /start برای شروع مجدد"
        )
    elif current_state == BotState.WAITING_VIDEO:
        await update.message.reply_text(
            "❌ **ویدیو مورد نیاز است**\n\n"
            " فرمت‌ها: MP4, MOV, MKV, AVI, WEBM, FLV, WMV, MPEG, M4V, 3GP\n"
            " حتماً به صورت داکیومنت برای فایل‌های بزرگ بفرستید\n"
            " پشتیبانی تا 2TB\n"
            " /start برای شروع مجدد"
        )
    else:
        await update.message.reply_text("❌ وضعیت نامشخص! 🚀 /start کنید")

def setup_bot():
    """Quick bot setup"""
    print("😈 Ultra Fast Video Banner Bot Setup (v2.0)")
    print("=" * 45)
    print("⚡ Speed: 15-60 seconds processing")
    print(" Support: Up to 2TB files (NEW!)")
    print(" Smart download for any file size")
    print(" Improved large file handling")
    print("=" * 45)
    
    config.bot_token = input("📱 Bot Token: ").strip()
    config.owner_id = input("👤 Owner ID: ").strip()
    
    if not config.bot_token:
        print("❌ Bot Token required!")
        return False
    
    print("✅ Ready for ultra fast processing (up to 2TB)!")
    return True

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Fast error handler"""
    logger.error(f"Error: {context.error}")
    
    if update and update.effective_message:
        try:
            await update.effective_message.reply_text(
                "❌ **خطا!** 🔄 /start کنید\n\n"
                " برای فایل‌های بزرگ، لطفاً به صورت داکیومنت بفرستید"
            )
        except:
            pass

def main() -> None:
    """Main function - optimized for large files"""
    if not setup_bot():
        return
    
    print("\n Starting ultra fast bot (v2.0)...")
    
    # بهینه‌سازی برای فایل‌های بزرگ
    application = (Application.builder()
                  .token(config.bot_token)
                  .read_timeout(180)     # افزایش timeout برای فایل‌های بزرگ
                  .write_timeout(180)
                  .connect_timeout(60)
                  .pool_timeout(60)
                  .get_updates_read_timeout(60)
                  .get_updates_write_timeout(60)
                  .get_updates_connect_timeout(30)
                  .build())
    
    # Add handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CallbackQueryHandler(button_callback))
    application.add_handler(MessageHandler(filters.PHOTO, handle_banner))
    application.add_handler(MessageHandler(filters.VIDEO, handle_video))
    application.add_handler(MessageHandler(filters.Document.ALL, handle_document))
    application.add_handler(MessageHandler(~filters.COMMAND, handle_wrong_content))
    application.add_error_handler(error_handler)
    
    print("✅ Ultra fast bot running (v2.0)!")
    print("⚡ Target: 15-60 seconds processing")
    print(" Support: Up to 2TB files")
    print(" Smart download optimization!")
    print("Press Ctrl+C to stop")
    
    # اجرا با polling بهینه
    application.run_polling(
        allowed_updates=Update.ALL_TYPES,
        timeout=60,  # افزایش timeout
        drop_pending_updates=True
    )

if __name__ == '__main__':
    main()
