#!/usr/bin/env python3
import os
import logging
import asyncio
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes, CallbackQueryHandler
from pyrogram import Client, filters as pyrogram_filters
from pyrogram.types import Message as PyrogramMessage
import subprocess
import tempfile
from enum import Enum
import math
import aiofiles
from concurrent.futures import ThreadPoolExecutor
import time
import threading

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
        # Bot API (برای پاسخ‌ها)
        self.bot_token = ""
        self.owner_id = ""
        
        # User Client API (برای دانلود)
        self.api_id = ""
        self.api_hash = ""
        self.phone_number = ""
        self.session_name = "video_bot_session"

config = VideoLogoBotConfig()

# Dictionary to store user states and banner paths
user_states = {}
user_banners = {}
pending_downloads = {}  # ذخیره اطلاعات دانلود

# Thread pool for CPU-intensive tasks
executor = ThreadPoolExecutor(max_workers=4)

# Pyrogram client (برای دانلود)
user_client = None

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

async def download_with_user_client(message_id, chat_id, output_path, progress_callback=None):
    """
    دانلود فایل با استفاده از User Client (بدون محدودیت 20MB)
    """
    try:
        if not user_client:
            logger.error("User client not initialized")
            return False
        
        # دریافت پیام از طریق user client
        message = await user_client.get_messages(chat_id, message_id)
        
        if not message:
            logger.error("Message not found")
            return False
        
        # تشخیص نوع فایل
        media = None
        if message.video:
            media = message.video
        elif message.document:
            media = message.document
        elif message.photo:
            media = message.photo
        else:
            logger.error("No supported media found")
            return False
        
        # دانلود با progress callback
        async def download_progress(current, total):
            if progress_callback:
                progress = (current / total) * 100 if total > 0 else 0
                await progress_callback(progress)
        
        # دانلود فایل
        downloaded_file = await user_client.download_media(
            message,
            file_name=output_path,
            progress=download_progress
        )
        
        if downloaded_file and os.path.exists(output_path):
            return True
        else:
            return False
            
    except Exception as e:
        logger.error(f"User client download error: {e}")
        return False

async def fallback_bot_download(bot, file_id, output_path, progress_callback=None):
    """
    دانلود با Bot API (fallback برای فایل‌های کوچک)
    """
    try:
        file_obj = await bot.get_file(file_id)
        await file_obj.download_to_drive(output_path)
        if progress_callback:
            await progress_callback(100)
        return True
    except Exception as e:
        logger.error(f"Bot download error: {e}")
        return False

async def smart_download(bot, message, output_path, progress_callback=None):
    """
    دانلود هوشمند - ابتدا User Client، سپس Bot API
    """
    try:
        # ذخیره اطلاعات پیام برای user client
        chat_id = message.chat_id
        message_id = message.message_id
        
        # تلاش با User Client
        if user_client:
            logger.info("Attempting download with User Client...")
            success = await download_with_user_client(
                message_id, chat_id, output_path, progress_callback
            )
            if success:
                logger.info("✅ Downloaded successfully with User Client")
                return True
            else:
                logger.warning("❌ User Client download failed, trying Bot API...")
        
        # Fallback به Bot API
        file_id = None
        if message.video:
            file_id = message.video.file_id
        elif message.document:
            file_id = message.document.file_id
        elif message.photo:
            file_id = message.photo[-1].file_id
        
        if file_id:
            logger.info("Attempting download with Bot API...")
            success = await fallback_bot_download(bot, file_id, output_path, progress_callback)
            if success:
                logger.info("✅ Downloaded successfully with Bot API")
                return True
        
        logger.error("❌ All download methods failed")
        return False
        
    except Exception as e:
        logger.error(f"Smart download error: {e}")
        return False

def run_ffmpeg_ultra_fast(input_video, input_banner, output_video):
    """Ultra fast FFmpeg processing optimized for speed"""
    try:
        cmd = [
            'ffmpeg', '-y',
            '-i', input_video,
            '-i', input_banner,
            '-filter_complex',
            '[1:v]scale=iw:ih:flags=fast_bilinear[banner];[0:v][banner]overlay=0:0:enable=\'between(t,0,1)\':format=auto[out]',
            '-map', '[out]',
            '-map', '0:a?',
            '-c:a', 'copy',
            '-c:v', 'libx264',
            '-preset', 'ultrafast',
            '-crf', '25',
            '-tune', 'fastdecode',
            '-threads', '0',
            '-bf', '0',
            '-refs', '1',
            '-sc_threshold', '0',
            '-g', '30',
            '-keyint_min', '30',
            '-movflags', '+faststart+frag_keyframe+empty_moov',
            '-fflags', '+genpts+flush_packets',
            '-avoid_negative_ts', 'disabled',
            '-max_muxing_queue_size', '2048',
            '-bufsize', '2M',
            '-maxrate', '100M',
            '-f', 'mp4',
            output_video
        ]
        
        result = subprocess.run(
            cmd, 
            capture_output=True, 
            text=True, 
            timeout=300,  # 5 دقیقه timeout
            check=False
        )
        
        return result.returncode == 0, result.stderr
        
    except subprocess.TimeoutExpired:
        return False, "Processing timeout - فایل خیلی بزرگ است"
    except Exception as e:
        return False, str(e)

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
    
    client_status = "✅ فعال" if user_client and user_client.is_connected else "❌ غیرفعال"
    
    welcome_message = f"""
🚀 **ربات فوق سریع اضافه کردن بنر به ویدیو (نسخه User Client)**

سلام! خوش آمدید ✅

⚡ **قابلیت‌های جدید:**
• ✅ دانلود با User Client API (بدون محدودیت 20MB)
• ✅ پشتیبانی فایل‌های تا 2GB+ 
• ✅ سرعت دانلود فوق‌العاده
• ✅ فالبک خودکار به Bot API
• 🔄 User Client: {client_status}

🎯 **مزایای User Client:**
• دانلود مستقیم فایل‌های بزرگ
• سرعت بالاتر برای فایل‌های +50MB
• بدون محدودیت Bot API
• پایداری بیشتر

📋 **فرمت‌های پشتیبانی:**
• ویدیو: MP4, MOV, MKV, AVI, WEBM, FLV, WMV, MPEG, M4V, 3GP
• بنر: JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC

📝 **نحوه استفاده:**
1️⃣ بنر را ارسال کنید
2️⃣ ویدیو را ارسال کنید (حجم بالا OK!)
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
    """Handle banner image upload"""
    user_id = update.effective_user.id
    
    if user_states.get(user_id) != BotState.WAITING_BANNER:
        await update.message.reply_text("❌ لطفاً ابتدا از دستور /start استفاده کنید")
        return
    
    start_time = time.time()
    
    try:
        processing_msg = await update.message.reply_text("⚡ دانلود هوشمند بنر...")
        
        photo = update.message.photo[-1]
        
        banner_temp = tempfile.NamedTemporaryFile(suffix='.jpg', delete=False)
        banner_path = banner_temp.name
        banner_temp.close()
        
        # استفاده از دانلود هوشمند
        async def progress_callback(progress):
            if progress % 20 == 0:  # هر 20% آپدیت
                try:
                    elapsed = time.time() - start_time
                    await processing_msg.edit_text(
                        f"⚡ دانلود بنر... {int(progress)}% ({elapsed:.1f}s)"
                    )
                except:
                    pass
        
        success = await smart_download(context.bot, update.message, banner_path, progress_callback)
        
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
        
        download_method = "User Client" if user_client and user_client.is_connected else "Bot API"
        
        await processing_msg.edit_text(
            f"✅ **بنر آماده شد!** ⚡ {elapsed:.1f}s\n\n"
            f"📊 حجم: {format_file_size(banner_size)}\n"
            f"🔄 روش: {download_method}\n\n"
            "📹 **حالا ویدیو را بفرستید (حجم بالا OK!)**\n\n"
            "💡 **نکات:**\n"
            "• فایل‌های بزرگ به صورت داکیومنت بفرستید\n"
            "• User Client محدودیت 20MB ندارد\n"
            "• حداکثر 60 ثانیه انتظار",
            parse_mode='Markdown'
        )
        
        user_states[user_id] = BotState.WAITING_VIDEO
        
    except Exception as e:
        logger.error(f"Banner error: {e}")
        await update.message.reply_text(f"❌ خطا در بنر: {str(e)[:50]}")

async def handle_video(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle video upload and processing"""
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
        
        # بررسی اندازه (تا 2GB)
        max_size = 2 * 1024 * 1024 * 1024  # 2GB
        if file_size > max_size:
            await update.message.reply_text(
                f"❌ حجم ویدیو ({format_file_size(file_size)}) بیش از 2GB است"
            )
            return
        
        # تخمین زمان بر اساس اندازه
        estimated_time = min(90, max(30, file_size // (5 * 1024 * 1024)))
        download_method = "User Client" if user_client and user_client.is_connected else "Bot API"
        
        processing_msg = await update.message.reply_text(
            f"🚀 **پردازش هوشمند شروع شد!**\n\n"
            f"📊 حجم: {format_file_size(file_size)}\n"
            f"🔄 روش: {download_method}\n"
            f"⏱️ تخمین: {estimated_time} ثانیه\n"
            f"⚡ در حال دانلود هوشمند..."
        )
        
        # Create temp files
        video_temp = tempfile.NamedTemporaryFile(suffix='.mp4', delete=False)
        video_path = video_temp.name
        video_temp.close()
        
        output_temp = tempfile.NamedTemporaryFile(suffix='.mp4', delete=False)
        output_path = output_temp.name
        output_temp.close()
        
        # دانلود با روش هوشمند
        download_start = time.time()
        
        async def smart_progress(progress):
            elapsed = time.time() - start_time
            remaining = max(0, estimated_time - elapsed)
            try:
                await processing_msg.edit_text(
                    f"⚡ **دانلود هوشمند... {int(progress)}%** ({elapsed:.1f}s)\n\n"
                    f"📊 حجم: {format_file_size(file_size)}\n"
                    f"🔄 روش: {download_method}\n"
                    f"⏱️ باقی‌مانده: ~{remaining:.0f}s\n"
                    f"🎯 User Client = بدون محدودیت!"
                )
            except:
                pass
        
        success = await smart_download(context.bot, update.message, video_path, smart_progress)
        
        if not success or not os.path.exists(video_path) or os.path.getsize(video_path) == 0:
            await processing_msg.edit_text(
                "❌ **خطا در دانلود ویدیو**\n\n"
                "💡 **پیشنهادات:**\n"
                "• ویدیو را به صورت داکیومنت بفرستید\n"
                "• اتصال اینترنت را بررسی کنید\n"
                "• از User Client استفاده می‌شود (بهتر از Bot API)\n"
                "• دوباره تلاش کنید"
            )
            return
        
        download_time = time.time() - download_start
        banner_path = user_banners[user_id]
        
        if not os.path.exists(banner_path):
            await processing_msg.edit_text("❌ بنر پیدا نشد. از /start شروع کنید")
            return
        
        # پردازش
        process_start = time.time()
        await processing_msg.edit_text(
            f"⚡ **پردازش ویدیو...** ({time.time() - start_time:.1f}s)\n\n"
            f"✅ دانلود: {download_time:.1f}s ({download_method})\n"
            f"🔄 در حال اضافه کردن بنر...\n"
            f"📊 پردازش {format_file_size(file_size)}"
        )
        
        # اجرای FFmpeg
        def run_ffmpeg():
            return run_ffmpeg_ultra_fast(video_path, banner_path, output_path)
        
        timeout_duration = max(90, file_size // (3 * 1024 * 1024))
        
        try:
            success, error_msg = await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(executor, run_ffmpeg),
                timeout=timeout_duration
            )
        except asyncio.TimeoutError:
            await processing_msg.edit_text(
                f"❌ **زمان پردازش تمام شد ({timeout_duration}s)**\n\n"
                "فایل خیلی بزرگ یا پیچیده است"
            )
            return
        
        process_time = time.time() - process_start
        
        if success and os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            total_time = time.time() - start_time
            output_size = os.path.getsize(output_path)
            
            await processing_msg.edit_text(
                f"✅ **آماده شد!** 🚀 {total_time:.1f}s\n\n"
                f"📊 حجم نهایی: {format_file_size(output_size)}\n"
                f"🔄 آپلود هوشمند..."
            )
            
            # آپلود
            with open(output_path, 'rb') as video_file_obj:
                if output_size > 50 * 1024 * 1024:  # >50MB
                    await update.message.reply_document(
                        document=video_file_obj,
                        caption=(
                            f"✅ **ویدیو آماده! (فایل بزرگ)** 🚀 {total_time:.1f}s\n\n"
                            f"⚡ دانلود: {download_time:.1f}s ({download_method})\n"
                            f"🔄 پردازش: {process_time:.1f}s\n"
                            f"📊 حجم: {format_file_size(output_size)}\n\n"
                            "🎯 **User Client** = دانلود بدون محدودیت!\n"
                            "📹 بنر در ثانیه اول\n"
                            "🔄 /start برای ویدیو جدید"
                        ),
                        parse_mode='Markdown'
                    )
                else:
                    await update.message.reply_video(
                        video=video_file_obj,
                        caption=(
                            f"✅ **ویدیو آماده!** 🚀 {total_time:.1f}s\n\n"
                            f"⚡ دانلود: {download_time:.1f}s ({download_method})\n"
                            f"🔄 پردازش: {process_time:.1f}s\n"
                            f"📊 حجم: {format_file_size(output_size)}\n\n"
                            "🎯 **User Client** فعال!\n"
                            "🔄 /start برای ویدیو جدید"
                        ),
                        parse_mode='Markdown'
                    )
            
            await processing_msg.delete()
            user_states[user_id] = BotState.IDLE
            
        else:
            await processing_msg.edit_text(
                f"❌ **خطا در پردازش** ({time.time() - start_time:.1f}s)\n\n"
                f"جزئیات: {error_msg[:100] if error_msg else 'نامشخص'}"
            )
                
    except Exception as e:
        elapsed = time.time() - start_time
        logger.error(f"Video processing error: {e}")
        await update.message.reply_text(
            f"❌ خطا ({elapsed:.1f}s): {str(e)[:80]}"
        )
        
    finally:
        # پاکسازی
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

async def handle_document(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle document upload"""
    user_id = update.effective_user.id
    document = update.message.document
    
    if not document:
        await handle_wrong_content(update, context)
        return
    
    if (user_states.get(user_id) == BotState.WAITING_VIDEO and 
        (is_supported_video(document) or 
         (document.file_name and document.file_name.lower().split('.')[-1] in 
          ['mp4', 'mov', 'mkv', 'avi', 'webm', 'flv', 'wmv', 'mpeg', 'm4v', '3gp']))):
        await handle_large_video_document(update, context)
        return
    
    if (user_states.get(user_id) == BotState.WAITING_BANNER and 
        (is_supported_image(document) or 
         (document.file_name and document.file_name.lower().split('.')[-1] in 
          ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tiff', 'svg', 'heic']))):
        await handle_banner_document(update, context)
        return
    
    await handle_wrong_content(update, context)

async def handle_banner_document(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle banner documents"""
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
                "📋 فرمت‌های مجاز: JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC"
            )
            return
        
        processing_msg = await update.message.reply_text("⚡ دانلود هوشمند بنر...")
        
        file_ext = '.jpg'
        if document.file_name:
            file_ext = '.' + document.file_name.lower().split('.')[-1]
        
        banner_temp = tempfile.NamedTemporaryFile(suffix=file_ext, delete=False)
        banner_path = banner_temp.name
        banner_temp.close()
        
        # استفاده از دانلود هوشمند
        success = await smart_download(context.bot, update.message, banner_path)
        
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
        download_method = "User Client" if user_client and user_client.is_connected else "Bot API"
        
        await processing_msg.edit_text(
            f"✅ **بنر آماده!** ⚡ {elapsed:.1f}s\n\n"
            f"📊 حجم: {format_file_size(banner_size)}\n"
            f"🔄 روش: {download_method}\n\n"
            "📹 **ویدیو را بفرستید (حجم بالا OK!)**\n"
            "🎯 User Client = بدون محدودیت 20MB!",
            parse_mode='Markdown'
        )
        
        user_states[user_id] = BotState.WAITING_VIDEO
        
    except Exception as e:
        logger.error(f"Banner document error: {e}")
        await update.message.reply_text(f"❌ خطا: {str(e)[:50]}")

async def handle_large_video_document(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle large video documents"""
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
                "📋 فرمت‌های مجاز: MP4, MOV, MKV, AVI, WEBM, FLV, WMV, MPEG, M4V, 3GP"
            )
            return
        
        max_size = 2 * 1024 * 1024 * 1024  # 2GB
        if file_size > max_size:
            await update.message.reply_text(
                f"❌ حجم ({format_file_size(file_size)}) بیش از 2GB است"
            )
            return
        
        # ایجاد mock video برای سازگاری
        class MockVideo:
            def __init__(self, document):
                self.file_id = document.file_id
                self.file_size = document.file_size
                self.mime_type = getattr(document, 'mime_type', 'video/mp4')
                self.file_name = getattr(document, 'file_name', 'video.mp4')
                self.duration = getattr(document, 'duration', 0)
        
        original_video = getattr(update.message, 'video', None)
        update.message.video = MockVideo(document)
        
        await handle_video(update, context)
        
        update.message.video = original_video
        
    except Exception as e:
        logger.error(f"Document video error: {e}")
        await update.message.reply_text(f"❌ خطا: {str(e)[:50]}")

async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle button callbacks"""
    query = update.callback_query
    user_id = query.from_user.id
    
    await query.answer()
    
    if query.data == "send_banner":
        user_states[user_id] = BotState.WAITING_BANNER
        client_status = "✅ فعال" if user_client and user_client.is_connected else "❌ غیرفعال"
        await query.edit_message_text(
            f"⚡ **بنر خود را فوری ارسال کنید**\n\n"
            f"📋 **فرمت‌های پشتیبانی شده:**\n"
            f"JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC\n\n"
            f"🎯 **مزایای User Client:**\n"
            f"• دانلود بدون محدودیت 20MB\n"
            f"• سرعت بالاتر برای فایل‌های بزرگ\n"
            f"• فالبک خودکار به Bot API\n"
            f"🔄 وضعیت: {client_status}\n\n"
            f"📹 بعد از بنر، ویدیو تا 2GB بفرستید!",
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
    """Handle wrong content type"""
    user_id = update.effective_user.id
    current_state = user_states.get(user_id, BotState.IDLE)
    
    if current_state == BotState.WAITING_BANNER:
        await update.message.reply_text(
            "❌ **بنر مورد نیاز است**\n\n"
            "📋 فرمت‌ها: JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC\n"
            "🎯 User Client: دانلود بدون محدودیت!\n"
            "🔄 /start برای شروع مجدد"
        )
    elif current_state == BotState.WAITING_VIDEO:
        await update.message.reply_text(
            "❌ **ویدیو مورد نیاز است**\n\n"
            "📋 فرمت‌ها: MP4, MOV, MKV, AVI, WEBM, FLV, WMV, MPEG, M4V, 3GP\n"
            "🎯 User Client: فایل‌های بزرگ OK!\n"
            "💡 به صورت داکیومنت برای فایل‌های +50MB\n"
            "🔄 /start برای شروع مجدد"
        )
    else:
        await update.message.reply_text("❌ وضعیت نامشخص! 🚀 /start کنید")

async def initialize_user_client():
    """Initialize Pyrogram user client"""
    global user_client
    
    try:
        user_client = Client(
            config.session_name,
            api_id=config.api_id,
            api_hash=config.api_hash,
            phone_number=config.phone_number
        )
        
        await user_client.start()
        logger.info("✅ User Client initialized successfully")
        return True
        
    except Exception as e:
        logger.error(f"❌ User Client initialization failed: {e}")
        user_client = None
        return False

def setup_bot():
    """Bot setup with User Client"""
    print("🚀 Ultra Fast Video Banner Bot Setup (User Client Edition)")
    print("=" * 60)
    print("⚡ Speed: 15-90 seconds processing")
    print("🎯 Support: Up to 2GB+ files (User Client)")
    print("📱 Smart download: User Client → Bot API fallback")
    print("🔄 No 20MB limit with User Client!")
    print("=" * 60)
    
    # Bot API credentials
    config.bot_token = input("📱 Bot Token: ").strip()
    config.owner_id = input("👤 Owner ID: ").strip()
    
    if not config.bot_token:
        print("❌ Bot Token required!")
        return False
    
    print("\n🔐 User Client API Setup (برای دانلود بدون محدودیت):")
    config.api_id = input("🔑 API ID (from my.telegram.org): ").strip()
    config.api_hash = input("🔐 API Hash: ").strip()
    config.phone_number = input("📞 Phone Number (+98912...): ").strip()
    
    if not all([config.api_id, config.api_hash, config.phone_number]):
        print("⚠️  User Client اختیاری است (فقط Bot API استفاده می‌شود)")
        print("✅ Ready with Bot API only (20MB limit)")
        return True
    
    try:
        config.api_id = int(config.api_id)
    except:
        print("❌ API ID باید عدد باشد!")
        return False
    
    print("✅ Ready with User Client support (no limits)!")
    return True

async def error_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Error handler"""
    logger.error(f"Error: {context.error}")
    
    if update and update.effective_message:
        try:
            await update.effective_message.reply_text(
                "❌ **خطا!** 🔄 /start کنید\n\n"
                "🎯 User Client برای فایل‌های بزرگ بهتر است"
            )
        except:
            pass

def main() -> None:
    """Main function"""
    if not setup_bot():
        return
    
    print("\n🚀 Starting ultra fast bot (User Client Edition)...")
    
    # ایجاد application
    application = (Application.builder()
                  .token(config.bot_token)
                  .read_timeout(300)
                  .write_timeout(300)
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
    
    # اجرای User Client در background
    async def run_with_user_client():
        # Initialize User Client if credentials provided
        if all([config.api_id, config.api_hash, config.phone_number]):
            await initialize_user_client()
        
        # Run bot
        await application.initialize()
        await application.start()
        await application.updater.start_polling(
            allowed_updates=Update.ALL_TYPES,
            timeout=60,
            drop_pending_updates=True
        )
        
        # Keep running
        try:
            await application.updater.idle()
        except KeyboardInterrupt:
            print("\n🛑 Stopping bot...")
        finally:
            await application.updater.stop()
            await application.stop()
            await application.shutdown()
            
            if user_client:
                await user_client.stop()
    
    print("✅ Ultra fast bot running (User Client Edition)!")
    print("🎯 Target: 15-90 seconds processing")
    print("📱 User Client: No 20MB limit!")
    print("🔄 Smart fallback to Bot API")
    print("Press Ctrl+C to stop")
    
    # اجرا
    asyncio.run(run_with_user_client())

if __name__ == '__main__':
    main()
