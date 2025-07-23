#!/usr/bin/env python3
"""
Ultra Fast Video Banner Bot - Professional Edition
ربات فوق سریع اضافه کردن بنر به ویدیو - نسخه حرفه‌ای

Author: itsMoji
GitHub: https://github.com/itsMoji/telegram-bot-api
Version: 2.0
"""

import os
import logging
import asyncio
import sys
import signal
import psutil
import tempfile
import math
import time
import threading
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Optional, List, Tuple
from enum import Enum
from concurrent.futures import ThreadPoolExecutor

# Telegram imports
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, BotCommand
from telegram.ext import (
    Application, CommandHandler, MessageHandler, 
    filters, ContextTypes, CallbackQueryHandler
)
from telegram.constants import ParseMode
from telegram.error import TelegramError, TimedOut, NetworkError

# Pyrogram imports
from pyrogram import Client
from pyrogram.errors import FloodWait, SessionPasswordNeeded

# System imports
import subprocess
import aiofiles
import uvloop

# Configure logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log', encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Configuration
from config import BotConfig

class BotState(Enum):
    """Bot state enumeration"""
    IDLE = "idle"
    WAITING_BANNER = "waiting_banner"
    WAITING_VIDEO = "waiting_video"
    PROCESSING = "processing"

class SystemStats:
    """System statistics tracking"""
    def __init__(self):
        self.start_time = datetime.now()
        self.processed_videos = 0
        self.total_processing_time = 0
        self.errors_count = 0
        self.largest_file_size = 0
        self.fastest_processing_time = float('inf')
        
    def update_processing_stats(self, processing_time: float, file_size: int):
        self.processed_videos += 1
        self.total_processing_time += processing_time
        self.largest_file_size = max(self.largest_file_size, file_size)
        self.fastest_processing_time = min(self.fastest_processing_time, processing_time)
    
    def get_uptime(self) -> str:
        uptime = datetime.now() - self.start_time
        return str(uptime).split('.')[0]
    
    def get_average_processing_time(self) -> float:
        if self.processed_videos == 0:
            return 0
        return self.total_processing_time / self.processed_videos

class VideoLogoBotPro:
    """Professional Video Logo Bot Implementation"""
    
    def __init__(self):
        self.config = BotConfig()
        self.stats = SystemStats()
        self.user_states: Dict[int, BotState] = {}
        self.user_banners: Dict[int, str] = {}
        self.processing_users: Dict[int, bool] = {}
        self.user_client: Optional[Client] = None
        self.executor = ThreadPoolExecutor(max_workers=4)
        
        # Supported formats
        self.SUPPORTED_VIDEO_FORMATS = {
            'video/mp4', 'video/quicktime', 'video/x-msvideo', 'video/x-matroska',
            'video/webm', 'video/x-flv', 'video/x-ms-wmv', 'video/mpeg',
            'video/mp4v-es', 'video/3gpp', 'application/octet-stream'
        }
        
        self.SUPPORTED_IMAGE_FORMATS = {
            'image/jpeg', 'image/png', 'image/webp', 'image/gif',
            'image/bmp', 'image/tiff', 'image/svg+xml', 'image/heic'
        }
    
    async def initialize_user_client(self) -> bool:
        """Initialize Pyrogram user client"""
        try:
            if not all([self.config.API_ID, self.config.API_HASH, self.config.PHONE_NUMBER]):
                logger.warning("User Client credentials not provided, using Bot API only")
                return False
            
            self.user_client = Client(
                self.config.SESSION_NAME,
                api_id=self.config.API_ID,
                api_hash=self.config.API_HASH,
                phone_number=self.config.PHONE_NUMBER,
                workdir="sessions"
            )
            
            await self.user_client.start()
            logger.info("✅ User Client initialized successfully")
            return True
            
        except SessionPasswordNeeded:
            logger.error("❌ 2FA password required for User Client")
            return False
        except Exception as e:
            logger.error(f"❌ User Client initialization failed: {e}")
            return False
    
    @staticmethod
    def format_file_size(size_bytes: int) -> str:
        """Format file size in human readable format"""
        if size_bytes == 0:
            return "0B"
        size_names = ["B", "KB", "MB", "GB", "TB"]
        i = int(math.floor(math.log(size_bytes, 1024)))
        p = math.pow(1024, i)
        s = round(size_bytes / p, 2)
        return f"{s} {size_names[i]}"
    
    async def smart_download(self, bot, message, output_path: str, progress_callback=None) -> bool:
        """Smart download with User Client fallback to Bot API"""
        try:
            # Try User Client first
            if self.user_client and await self._download_with_user_client(
                message, output_path, progress_callback
            ):
                return True
            
            # Fallback to Bot API
            return await self._download_with_bot_api(bot, message, output_path, progress_callback)
            
        except Exception as e:
            logger.error(f"Smart download error: {e}")
            return False
    
    async def _download_with_user_client(self, message, output_path: str, progress_callback=None) -> bool:
        """Download using User Client"""
        try:
            if not self.user_client:
                return False
            
            chat_id = message.chat_id
            message_id = message.message_id
            
            # Get message through user client
            user_message = await self.user_client.get_messages(chat_id, message_id)
            if not user_message:
                return False
            
            # Download with progress
            async def download_progress(current, total):
                if progress_callback and total > 0:
                    progress = (current / total) * 100
                    await progress_callback(progress)
            
            downloaded_file = await self.user_client.download_media(
                user_message,
                file_name=output_path,
                progress=download_progress
            )
            
            return downloaded_file and os.path.exists(output_path) and os.path.getsize(output_path) > 0
            
        except FloodWait as e:
            logger.warning(f"Flood wait: {e.value} seconds")
            await asyncio.sleep(e.value)
            return False
        except Exception as e:
            logger.error(f"User client download error: {e}")
            return False
    
    async def _download_with_bot_api(self, bot, message, output_path: str, progress_callback=None) -> bool:
        """Download using Bot API"""
        try:
            file_id = None
            if message.video:
                file_id = message.video.file_id
            elif message.document:
                file_id = message.document.file_id
            elif message.photo:
                file_id = message.photo[-1].file_id
            
            if not file_id:
                return False
            
            file_obj = await bot.get_file(file_id)
            await file_obj.download_to_drive(output_path)
            
            if progress_callback:
                await progress_callback(100)
            
            return os.path.exists(output_path) and os.path.getsize(output_path) > 0
            
        except Exception as e:
            logger.error(f"Bot API download error: {e}")
            return False
    
    def run_ffmpeg_ultra_fast(self, input_video: str, input_banner: str, output_video: str) -> Tuple[bool, str]:
        """Ultra fast FFmpeg processing"""
        try:
            cmd = [
                'ffmpeg', '-y', '-hide_banner',
                '-i', input_video,
                '-i', input_banner,
                '-filter_complex',
                '[1:v]scale=iw:ih:flags=fast_bilinear[banner];'
                '[0:v][banner]overlay=0:0:enable=\'between(t,0,1)\':format=auto[out]',
                '-map', '[out]',
                '-map', '0:a?',
                '-c:a', 'copy',
                '-c:v', 'libx264',
                '-preset', 'ultrafast',
                '-crf', '23',
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
                '-max_muxing_queue_size', '4096',
                '-bufsize', '4M',
                '-maxrate', '200M',
                '-f', 'mp4',
                output_video
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=600,  # 10 minutes timeout
                check=False
            )
            
            return result.returncode == 0, result.stderr
            
        except subprocess.TimeoutExpired:
            return False, "Processing timeout - فایل خیلی بزرگ است"
        except Exception as e:
            return False, str(e)
    
    def cleanup_temp_files(self, *file_paths):
        """Clean up temporary files"""
        for file_path in file_paths:
            if file_path and os.path.exists(file_path):
                try:
                    os.unlink(file_path)
                except Exception as e:
                    logger.warning(f"Failed to cleanup {file_path}: {e}")
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Start command handler"""
        user_id = update.effective_user.id
        
        # Reset user state
        self.user_states[user_id] = BotState.IDLE
        if user_id in self.user_banners:
            self.cleanup_temp_files(self.user_banners[user_id])
            del self.user_banners[user_id]
        
        client_status = "✅ فعال" if self.user_client else "❌ غیرفعال"
        
        welcome_message = f"""
🚀 **ربات حرفه‌ای اضافه کردن بنر به ویدیو**

سلام {update.effective_user.first_name}! 👋

⚡ **قابلیت‌های پیشرفته:**
• ✅ دانلود هوشمند با User Client API
• ✅ پشتیبانی فایل‌های تا 2GB+ 
• ✅ پردازش فوق سریع با FFmpeg
• ✅ پایداری و بازیابی خودکار خطا
• 🔄 User Client: {client_status}

📊 **آمار سیستم:**
• 🎯 ویدیوهای پردازش شده: {self.stats.processed_videos}
• ⏱️ مدت فعالیت: {self.stats.get_uptime()}
• 💾 بزرگ‌ترین فایل: {self.format_file_size(self.stats.largest_file_size)}

📋 **فرمت‌های پشتیبانی:**
• ویدیو: MP4, MOV, MKV, AVI, WEBM, FLV, WMV, M4V, 3GP
• بنر: JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC

🚀 **شروع کنید!**
"""
        
        keyboard = [
            [
                InlineKeyboardButton("⚡ ارسال بنر", callback_data="send_banner"),
                InlineKeyboardButton("📊 آمار", callback_data="stats")
            ],
            [
                InlineKeyboardButton("❓ راهنما", callback_data="help"),
                InlineKeyboardButton("⚙️ تنظیمات", callback_data="settings")
            ]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await update.message.reply_text(
            welcome_message,
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )
        
        self.user_states[user_id] = BotState.WAITING_BANNER
    
    async def handle_banner(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle banner image upload"""
        user_id = update.effective_user.id
        
        if self.user_states.get(user_id) != BotState.WAITING_BANNER:
            await update.message.reply_text("❌ لطفاً ابتدا از دستور /start استفاده کنید")
            return
        
        start_time = time.time()
        
        try:
            processing_msg = await update.message.reply_text("⚡ دانلود هوشمند بنر...")
            
            # Create temp file for banner
            banner_temp = tempfile.NamedTemporaryFile(
                suffix='.jpg', 
                delete=False,
                dir=self.config.TEMP_DIR
            )
            banner_path = banner_temp.name
            banner_temp.close()
            
            # Progress callback
            async def progress_callback(progress):
                if int(progress) % 25 == 0:
                    try:
                        elapsed = time.time() - start_time
                        await processing_msg.edit_text(
                            f"⚡ دانلود بنر... {int(progress)}% ({elapsed:.1f}s)"
                        )
                    except:
                        pass
            
            # Smart download
            success = await self.smart_download(
                context.bot, update.message, banner_path, progress_callback
            )
            
            if not success:
                await processing_msg.edit_text("❌ خطا در دانلود بنر. دوباره تلاش کنید.")
                self.cleanup_temp_files(banner_path)
                return
            
            self.user_banners[user_id] = banner_path
            
            elapsed = time.time() - start_time
            banner_size = os.path.getsize(banner_path)
            download_method = "User Client" if self.user_client else "Bot API"
            
            await processing_msg.edit_text(
                f"✅ **بنر آماده!** ⚡ {elapsed:.1f}s\n\n"
                f"📊 حجم: {self.format_file_size(banner_size)}\n"
                f"🔄 روش: {download_method}\n\n"
                "📹 **ویدیو را بفرستید (حجم بالا OK!)**",
                parse_mode=ParseMode.MARKDOWN
            )
            
            self.user_states[user_id] = BotState.WAITING_VIDEO
            
        except Exception as e:
            logger.error(f"Banner error: {e}")
            await update.message.reply_text(f"❌ خطا در بنر: {str(e)[:50]}")
            self.stats.errors_count += 1
    
    async def handle_video(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle video upload and processing"""
        user_id = update.effective_user.id
        
        if self.user_states.get(user_id) != BotState.WAITING_VIDEO:
            await update.message.reply_text("❌ لطفاً ابتدا بنر خود را ارسال کنید")
            return
        
        if user_id not in self.user_banners:
            await update.message.reply_text("❌ بنر پیدا نشد. از /start شروع کنید")
            return
        
        if user_id in self.processing_users:
            await update.message.reply_text("⚠️ در حال پردازش ویدیو قبلی هستید")
            return
        
        self.processing_users[user_id] = True
        self.user_states[user_id] = BotState.PROCESSING
        start_time = time.time()
        
        video_path = None
        output_path = None
        
        try:
            # Get video info
            video = getattr(update.message, 'video', None) or getattr(update.message, 'document', None)
            if not video:
                await update.message.reply_text("❌ فایل ویدیو پیدا نشد")
                return
            
            file_size = getattr(video, 'file_size', 0)
            
            # Size check
            max_size = self.config.MAX_FILE_SIZE
            if file_size > max_size:
                await update.message.reply_text(
                    f"❌ حجم ({self.format_file_size(file_size)}) بیش از حد مجاز است"
                )
                return
            
            # Estimate processing time
            estimated_time = min(180, max(30, file_size // (3 * 1024 * 1024)))
            download_method = "User Client" if self.user_client else "Bot API"
            
            processing_msg = await update.message.reply_text(
                f"🚀 **پردازش حرفه‌ای شروع شد!**\n\n"
                f"📊 حجم: {self.format_file_size(file_size)}\n"
                f"🔄 روش: {download_method}\n"
                f"⏱️ تخمین: {estimated_time}s\n"
                f"⚡ دانلود هوشمند...",
                parse_mode=ParseMode.MARKDOWN
            )
            
            # Create temp files
            video_temp = tempfile.NamedTemporaryFile(
                suffix='.mp4', 
                delete=False,
                dir=self.config.TEMP_DIR
            )
            video_path = video_temp.name
            video_temp.close()
            
            output_temp = tempfile.NamedTemporaryFile(
                suffix='.mp4', 
                delete=False,
                dir=self.config.TEMP_DIR
            )
            output_path = output_temp.name
            output_temp.close()
            
            # Download video
            download_start = time.time()
            
            async def smart_progress(progress):
                elapsed = time.time() - start_time
                remaining = max(0, estimated_time - elapsed)
                try:
                    await processing_msg.edit_text(
                        f"⚡ **دانلود... {int(progress)}%** ({elapsed:.1f}s)\n\n"
                        f"📊 حجم: {self.format_file_size(file_size)}\n"
                        f"🔄 روش: {download_method}\n"
                        f"⏱️ باقی‌مانده: ~{remaining:.0f}s",
                        parse_mode=ParseMode.MARKDOWN
                    )
                except:
                    pass
            
            success = await self.smart_download(
                context.bot, update.message, video_path, smart_progress
            )
            
            if not success:
                await processing_msg.edit_text("❌ خطا در دانلود ویدیو")
                return
            
            download_time = time.time() - download_start
            banner_path = self.user_banners[user_id]
            
            # Process video
            process_start = time.time()
            await processing_msg.edit_text(
                f"⚡ **پردازش ویدیو...** ({time.time() - start_time:.1f}s)\n\n"
                f"✅ دانلود: {download_time:.1f}s\n"
                f"🔄 اضافه کردن بنر...",
                parse_mode=ParseMode.MARKDOWN
            )
            
            # Run FFmpeg
            def run_ffmpeg():
                return self.run_ffmpeg_ultra_fast(video_path, banner_path, output_path)
            
            try:
                success, error_msg = await asyncio.wait_for(
                    asyncio.get_event_loop().run_in_executor(self.executor, run_ffmpeg),
                    timeout=300
                )
            except asyncio.TimeoutError:
                await processing_msg.edit_text("❌ زمان پردازش تمام شد")
                return
            
            process_time = time.time() - process_start
            
            if success and os.path.exists(output_path) and os.path.getsize(output_path) > 0:
                total_time = time.time() - start_time
                output_size = os.path.getsize(output_path)
                
                # Update stats
                self.stats.update_processing_stats(total_time, file_size)
                
                await processing_msg.edit_text(
                    f"✅ **آماده!** 🚀 {total_time:.1f}s\n\n"
                    f"📊 حجم نهایی: {self.format_file_size(output_size)}\n"
                    f"🔄 آپلود...",
                    parse_mode=ParseMode.MARKDOWN
                )
                
                # Upload result
                async with aiofiles.open(output_path, 'rb') as video_file:
                    video_content = await video_file.read()
                
                caption = (
                    f"✅ **ویدیو آماده!** 🚀 {total_time:.1f}s\n"
                    f"⚡ دانلود: {download_time:.1f}s ({download_method})\n"
                    f"🔄 پردازش: {process_time:.1f}s\n"
                    f"📊 حجم: {self.format_file_size(output_size)}\n\n"
                    f"🎯 **User Client فعال!**\n"
                    f"🔄 /start برای ویدیو جدید"
                )
                
                if output_size > 50 * 1024 * 1024:  # >50MB as document
                    await update.message.reply_document(
                        document=video_content,
                        caption=caption,
                        parse_mode=ParseMode.MARKDOWN
                    )
                else:
                    await update.message.reply_video(
                        video=video_content,
                        caption=caption,
                        parse_mode=ParseMode.MARKDOWN
                    )
                
                await processing_msg.delete()
                self.user_states[user_id] = BotState.IDLE
                
            else:
                await processing_msg.edit_text(
                    f"❌ **خطا در پردازش**\n"
                    f"جزئیات: {error_msg[:100] if error_msg else 'نامشخص'}"
                )
                self.stats.errors_count += 1
                
        except Exception as e:
            elapsed = time.time() - start_time
            logger.error(f"Video processing error: {e}")
            await update.message.reply_text(f"❌ خطا ({elapsed:.1f}s): {str(e)[:80]}")
            self.stats.errors_count += 1
            
        finally:
            # Cleanup
            self.cleanup_temp_files(video_path, output_path)
            if user_id in self.user_banners:
                self.cleanup_temp_files(self.user_banners[user_id])
                del self.user_banners[user_id]
            
            if user_id in self.processing_users:
                del self.processing_users[user_id]
    
    async def handle_document(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle document upload"""
        user_id = update.effective_user.id
        document = update.message.document
        
        if not document:
            await self.handle_wrong_content(update, context)
            return
        
        # Check if it's a video document
        if (self.user_states.get(user_id) == BotState.WAITING_VIDEO and 
            self._is_supported_video(document)):
            await self.handle_video(update, context)
            return
        
        # Check if it's a banner document
        if (self.user_states.get(user_id) == BotState.WAITING_BANNER and 
            self._is_supported_image(document)):
            await self.handle_banner(update, context)
            return
        
        await self.handle_wrong_content(update, context)
    
    def _is_supported_image(self, file_obj) -> bool:
        """Check if file is supported image format"""
        if hasattr(file_obj, 'mime_type') and file_obj.mime_type:
            return file_obj.mime_type in self.SUPPORTED_IMAGE_FORMATS
        if hasattr(file_obj, 'file_name') and file_obj.file_name:
            ext = file_obj.file_name.lower().split('.')[-1]
            return ext in ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tiff', 'svg', 'heic']
        return True
    
    def _is_supported_video(self, file_obj) -> bool:
        """Check if file is supported video format"""
        if hasattr(file_obj, 'mime_type') and file_obj.mime_type:
            return file_obj.mime_type in self.SUPPORTED_VIDEO_FORMATS
        if hasattr(file_obj, 'file_name') and file_obj.file_name:
            ext = file_obj.file_name.lower().split('.')[-1]
            return ext in ['mp4', 'mov', 'mkv', 'avi', 'webm', 'flv', 'wmv', 'mpeg', 'm4v', '3gp']
        return True
    
    async def handle_wrong_content(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle wrong content type"""
        user_id = update.effective_user.id
        current_state = self.user_states.get(user_id, BotState.IDLE)
        
        if current_state == BotState.WAITING_BANNER:
            await update.message.reply_text(
                "❌ **بنر مورد نیاز است**\n\n"
                "📋 فرمت‌ها: JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC\n"
                "🔄 /start برای شروع مجدد"
            )
        elif current_state == BotState.WAITING_VIDEO:
            await update.message.reply_text(
                "❌ **ویدیو مورد نیاز است**\n\n"
                "📋 فرمت‌ها: MP4, MOV, MKV, AVI, WEBM, FLV, WMV, M4V, 3GP\n"
                "🔄 /start برای شروع مجدد"
            )
        else:
            await update.message.reply_text("❌ وضعیت نامشخص! 🚀 /start کنید")
    
    async def button_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle button callbacks"""
        query = update.callback_query
        user_id = query.from_user.id
        
        await query.answer()
        
        if query.data == "send_banner":
            self.user_states[user_id] = BotState.WAITING_BANNER
            client_status = "✅ فعال" if self.user_client else "❌ غیرفعال"
            await query.edit_message_text(
                f"⚡ **بنر خود را ارسال کنید**\n\n"
                f"📋 فرمت‌های پشتیبانی: JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC\n\n"
                f"🎯 **مزایای User Client:**\n"
                f"• دانلود بدون محدودیت 20MB\n"
                f"• سرعت بالاتر\n"
                f"• فالبک خودکار\n"
                f"🔄 وضعیت: {client_status}",
                parse_mode=ParseMode.MARKDOWN
            )
        
        elif query.data == "stats":
            await self._show_stats(query)
        
        elif query.data == "help":
            await self._show_help(query)
        
        elif query.data == "settings":
            await self._show_settings(query)
    
    async def _show_stats(self, query):
        """Show system statistics"""
        system_info = psutil.virtual_memory()
        cpu_percent = psutil.cpu_percent(interval=1)
        
        stats_text = f"""
📊 **آمار سیستم**

🎯 **عملکرد بات:**
• ویدیوهای پردازش شده: {self.stats.processed_videos}
• میانگین زمان پردازش: {self.stats.get_average_processing_time():.1f}s
• سریع‌ترین پردازش: {self.stats.fastest_processing_time if self.stats.fastest_processing_time != float('inf') else 0:.1f}s
• بزرگ‌ترین فایل: {self.format_file_size(self.stats.largest_file_size)}
• خطاها: {self.stats.errors_count}

💻 **سیستم:**
• مدت فعالیت: {self.stats.get_uptime()}
• استفاده CPU: {cpu_percent}%
• استفاده RAM: {system_info.percent}%
• RAM آزاد: {self.format_file_size(system_info.available)}

🔄 **User Client:** {"✅ فعال" if self.user_client else "❌ غیرفعال"}
"""
        
        keyboard = [[InlineKeyboardButton("🔙 بازگشت", callback_data="back_to_main")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            stats_text,
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )
    
    async def _show_help(self, query):
        """Show help information"""
        help_text = """
❓ **راهنمای استفاده**

🚀 **مراحل کار:**
1️⃣ /start - شروع بات
2️⃣ بنر را ارسال کنید
3️⃣ ویدیو را ارسال کنید
4️⃣ ویدیو نهایی را دریافت کنید

📋 **فرمت‌های پشتیبانی:**
• **ویدیو:** MP4, MOV, MKV, AVI, WEBM, FLV, WMV, MPEG, M4V, 3GP
• **بنر:** JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC

⚡ **نکات مهم:**
• فایل‌های بزرگ را به صورت داکیومنت بفرستید
• User Client محدودیت 20MB ندارد
• پردازش 15-180 ثانیه طول می‌کشد
• بنر در ثانیه اول ویدیو اضافه می‌شود

🔧 **دستورات:**
• /start - شروع مجدد
• /stats - آمار سیستم
• /help - این راهنما
"""
        
        keyboard = [[InlineKeyboardButton("🔙 بازگشت", callback_data="back_to_main")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            help_text,
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )
    
    async def _show_settings(self, query):
        """Show settings"""
        settings_text = f"""
⚙️ **تنظیمات سیستم**

🔧 **پیکربندی فعلی:**
• حداکثر اندازه فایل: {self.format_file_size(self.config.MAX_FILE_SIZE)}
• دایرکتوری موقت: {self.config.TEMP_DIR}
• تعداد Thread: {self.executor._max_workers}
• User Client: {"✅ فعال" if self.user_client else "❌ غیرفعال"}

📊 **تنظیمات FFmpeg:**
• Preset: ultrafast
• CRF: 23
• Codec: libx264
• Max Rate: 200M

⚠️ **تنظیمات پیشرفته فقط برای ادمین**
"""
        
        keyboard = [[InlineKeyboardButton("🔙 بازگشت", callback_data="back_to_main")]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await query.edit_message_text(
            settings_text,
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=reply_markup
        )
    
    async def stats_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Stats command handler"""
        await self._show_stats_message(update.message)
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Help command handler"""
        await self._show_help_message(update.message)
    
    async def _show_stats_message(self, message):
        """Show stats as message"""
        system_info = psutil.virtual_memory()
        cpu_percent = psutil.cpu_percent(interval=1)
        
        stats_text = f"""
📊 **آمار سیستم**

🎯 ویدیوهای پردازش شده: {self.stats.processed_videos}
⏱️ میانگین زمان: {self.stats.get_average_processing_time():.1f}s
🚀 سریع‌ترین: {self.stats.fastest_processing_time if self.stats.fastest_processing_time != float('inf') else 0:.1f}s
💾 بزرگ‌ترین فایل: {self.format_file_size(self.stats.largest_file_size)}
❌ خطاها: {self.stats.errors_count}

💻 مدت فعالیت: {self.stats.get_uptime()}
🔄 CPU: {cpu_percent}% | RAM: {system_info.percent}%
"""
        
        await message.reply_text(stats_text, parse_mode=ParseMode.MARKDOWN)
    
    async def _show_help_message(self, message):
        """Show help as message"""
        help_text = """
❓ **راهنما**

🚀 /start - شروع
📊 /stats - آمار
❓ /help - راهنما

📋 **فرمت‌ها:**
ویدیو: MP4, MOV, MKV, AVI, WEBM, FLV, WMV, MPEG, M4V, 3GP
بنر: JPG, PNG, WEBP, GIF, BMP, TIFF, SVG, HEIC

⚡ **نکات:**
• فایل‌های بزرگ = داکیومنت
• User Client = بدون محدودیت 20MB
• پردازش: 15-180 ثانیه
"""
        
        await message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)
    
    async def error_handler(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Global error handler"""
        logger.error(f"Error: {context.error}")
        
        if update and update.effective_message:
            try:
                await update.effective_message.reply_text(
                    "❌ **خطای سیستم!**\n\n"
                    "🔄 /start کنید یا چند لحظه صبر کنید",
                    parse_mode=ParseMode.MARKDOWN
                )
            except:
                pass
        
        self.stats.errors_count += 1
    
    async def setup_bot_commands(self, application):
        """Setup bot commands"""
        commands = [
            BotCommand("start", "شروع بات"),
            BotCommand("help", "راهنمای استفاده"),
            BotCommand("stats", "آمار سیستم"),
        ]
        
        await application.bot.set_my_commands(commands)
    
    async def run(self):
        """Main run method"""
        try:
            # Setup directories
            Path(self.config.TEMP_DIR).mkdir(exist_ok=True)
            Path("sessions").mkdir(exist_ok=True)
            Path("logs").mkdir(exist_ok=True)
            
            # Initialize User Client
            if self.config.USE_USER_CLIENT:
                await self.initialize_user_client()
            
            # Create application
            application = (
                Application.builder()
                .token(self.config.BOT_TOKEN)
                .read_timeout(300)
                .write_timeout(300)
                .connect_timeout(60)
                .pool_timeout(60)
                .get_updates_read_timeout(60)
                .get_updates_write_timeout(60)
                .get_updates_connect_timeout(30)
                .build()
            )
            
            # Add handlers
            application.add_handler(CommandHandler("start", self.start_command))
            application.add_handler(CommandHandler("help", self.help_command))
            application.add_handler(CommandHandler("stats", self.stats_command))
            application.add_handler(CallbackQueryHandler(self.button_callback))
            application.add_handler(MessageHandler(filters.PHOTO, self.handle_banner))
            application.add_handler(MessageHandler(filters.VIDEO, self.handle_video))
            application.add_handler(MessageHandler(filters.Document.ALL, self.handle_document))
            application.add_handler(MessageHandler(~filters.COMMAND, self.handle_wrong_content))
            application.add_error_handler(self.error_handler)
            
            # Setup bot commands
            await self.setup_bot_commands(application)
            
            # Initialize and start
            await application.initialize()
            await application.start()
            await application.updater.start_polling(
                allowed_updates=Update.ALL_TYPES,
                timeout=60,
                drop_pending_updates=True
            )
            
            logger.info("✅ Bot started successfully!")
            logger.info(f"🎯 Target processing time: 15-180 seconds")
            logger.info(f"📱 User Client: {'✅ Active' if self.user_client else '❌ Inactive'}")
            logger.info(f"🔄 Smart fallback enabled")
            
            # Keep running
            try:
                await application.updater.idle()
            except KeyboardInterrupt:
                logger.info("🛑 Stopping bot...")
            finally:
                await application.updater.stop()
                await application.stop()
                await application.shutdown()
                
                if self.user_client:
                    await self.user_client.stop()
                
                self.executor.shutdown(wait=True)
                
        except Exception as e:
            logger.error(f"❌ Bot startup failed: {e}")
            raise

def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logger.info(f"Received signal {signum}, shutting down...")
    sys.exit(0)

async def main():
    """Main entry point"""
    # Set event loop policy for better performance
    if sys.platform != 'win32':
        uvloop.install()
    
    # Setup signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Create and run bot
    bot = VideoLogoBotPro()
    await bot.run()

if __name__ == '__main__':
    print("🚀 Ultra Fast Video Banner Bot Pro - Starting...")
    print("=" * 60)
    
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n🛑 Bot stopped by user")
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)
