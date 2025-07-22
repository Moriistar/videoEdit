#!/usr/bin/env python3
import os
import logging
import asyncio
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes, CallbackQueryHandler
import subprocess
import tempfile
from enum import Enum

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

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Start command handler"""
    user_id = update.effective_user.id
    
    # Reset user state
    user_states[user_id] = BotState.IDLE
    if user_id in user_banners:
        # Clean up old banner file
        old_banner = user_banners[user_id]
        if os.path.exists(old_banner):
            os.unlink(old_banner)
        del user_banners[user_id]
    
    welcome_message = """
🎬 **ربات اضافه کردن بنر به ویدیو**

سلام! خوش آمدید 👋

🎯 **قابلیت‌های من:**
• ✅ اضافه کردن بنر دلخواه شما به ویدیو
• ✅ نمایش بنر در ثانیه اول ویدیو
• ✅ حفظ کیفیت اصلی ویدیو
• ✅ سرعت پردازش بالا

📝 **نحوه استفاده:**
1️⃣ ابتدا بنر مورد نظرتان را ارسال کنید
2️⃣ سپس ویدیو مورد نظر را ارسال کنید
3️⃣ ویدیو نهایی را دریافت کنید

🚀 **برای شروع، لطفاً بنر خود را بفرستید!**
"""
    
    # Create inline keyboard
    keyboard = [
        [InlineKeyboardButton("📤 ارسال بنر", callback_data="send_banner")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        welcome_message, 
        parse_mode='Markdown',
        reply_markup=reply_markup
    )
    
    # Set state to waiting for banner
    user_states[user_id] = BotState.WAITING_BANNER

async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle button callbacks"""
    query = update.callback_query
    user_id = query.from_user.id
    
    await query.answer()
    
    if query.data == "send_banner":
        user_states[user_id] = BotState.WAITING_BANNER
        await query.edit_message_text(
            "📸 **لطفاً بنر مورد نظر خود را ارسال کنید**\n\n"
            "📋 **نکات مهم:**\n"
            "• بنر باید به صورت عکس باشد\n"
            "• کیفیت مناسب داشته باشد\n"
            "• در ثانیه اول ویدیو نمایش داده می‌شود",
            parse_mode='Markdown'
        )

async def handle_banner(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle banner image upload"""
    user_id = update.effective_user.id
    
    # Check if user is in correct state
    if user_states.get(user_id) != BotState.WAITING_BANNER:
        await update.message.reply_text(
            "❌ لطفاً ابتدا از دستور /start استفاده کنید"
        )
        return
    
    try:
        # Send confirmation message
        processing_msg = await update.message.reply_text("📥 در حال دریافت بنر...")
        
        # Get the largest photo size
        photo = update.message.photo[-1]
        photo_file = await context.bot.get_file(photo.file_id)
        
        # Create temporary file for banner
        banner_temp = tempfile.NamedTemporaryFile(suffix='.jpg', delete=False)
        banner_path = banner_temp.name
        banner_temp.close()
        
        # Download banner
        await photo_file.download_to_drive(banner_path)
        
        # Store banner path for user
        user_banners[user_id] = banner_path
        
        await processing_msg.edit_text(
            "✅ **بنر با موفقیت دریافت شد!**\n\n"
            "🎬 **حالا ویدیو مورد نظر خود را ارسال کنید**\n\n"
            "📋 **نکات:**\n"
            "• حداکثر حجم: 50 مگابایت\n"
            "• فرمت‌های مجاز: MP4, MOV, AVI\n"
            "• کیفیت اصلی حفظ می‌شود",
            parse_mode='Markdown'
        )
        
        # Change state to waiting for video
        user_states[user_id] = BotState.WAITING_VIDEO
        
    except Exception as e:
        logger.error(f"Error handling banner: {e}")
        await update.message.reply_text("❌ خطا در دریافت بنر. لطفاً دوباره تلاش کنید.")

async def handle_video(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle video upload and processing"""
    user_id = update.effective_user.id
    
    # Check if user is in correct state
    if user_states.get(user_id) != BotState.WAITING_VIDEO:
        await update.message.reply_text(
            "❌ لطفاً ابتدا بنر خود را ارسال کنید"
        )
        return
    
    # Check if user has uploaded banner
    if user_id not in user_banners:
        await update.message.reply_text(
            "❌ لطفاً ابتدا بنر خود را ارسال کنید"
        )
        return
    
    try:
        # Send processing message
        processing_msg = await update.message.reply_text(
            "🔄 **در حال آماده‌سازی...**\n\n"
            "⏳ این فرآیند بین چند ثانیه تا یک دقیقه طول می‌کشد\n"
            "📱 لطفاً صبر کنید..."
        )
        
        # Download video
        video_file = await context.bot.get_file(update.message.video.file_id)
        
        # Create temporary files
        video_temp = tempfile.NamedTemporaryFile(suffix='.mp4', delete=False)
        video_path = video_temp.name
        video_temp.close()
        
        output_temp = tempfile.NamedTemporaryFile(suffix='.mp4', delete=False)
        output_path = output_temp.name
        output_temp.close()
        
        # Download video
        await video_file.download_to_drive(video_path)
        
        # Get banner path
        banner_path = user_banners[user_id]
        
        # Update processing message
        await processing_msg.edit_text(
            "⚡ **در حال پردازش ویدیو...**\n\n"
            "🎨 بنر در حال اضافه شدن به ویدیو\n"
            "⏳ لطفاً صبر کنید..."
        )
        
        # FFmpeg command to add banner in first second (full screen)
        ffmpeg_cmd = [
            'ffmpeg', '-i', video_path,
            '-i', banner_path,
            '-filter_complex',
            '[1:v]scale=iw:ih[banner];[0:v][banner]overlay=0:0:enable=\'between(t,0,1)\'[out]',
            '-map', '[out]',
            '-map', '0:a?',
            '-c:a', 'copy',
            '-c:v', 'libx264',
            '-preset', 'fast',
            '-crf', '23',
            output_path,
            '-y'
        ]
        
        # Execute FFmpeg asynchronously
        try:
            process = await asyncio.create_subprocess_exec(
                *ffmpeg_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await process.communicate()
            
            if process.returncode == 0:
                # Check file size (Telegram limit is 50MB)
                file_size = os.path.getsize(output_path)
                if file_size > 50 * 1024 * 1024:  # 50MB in bytes
                    await processing_msg.edit_text(
                        "❌ **خطا!**\n\n"
                        "حجم ویدیو نهایی بیش از حد مجاز تلگرام است (50MB)\n"
                        "لطفاً ویدیو کوچک‌تری ارسال کنید"
                    )
                    return
                
                # Update message
                await processing_msg.edit_text(
                    "✅ **آماده شد!**\n\n"
                    "📤 در حال ارسال ویدیو نهایی..."
                )
                
                # Send processed video
                with open(output_path, 'rb') as video_file_obj:
                    await update.message.reply_video(
                        video=video_file_obj,
                        caption=(
                            "🎉 **ویدیو با بنر آماده شد!**\n\n"
                            "✨ بنر در ثانیه اول ویدیو نمایش داده می‌شود\n"
                            "🔄 برای ساخت ویدیو جدید از /start استفاده کنید"
                        ),
                        parse_mode='Markdown'
                    )
                
                await processing_msg.delete()
                
                # Reset user state
                user_states[user_id] = BotState.IDLE
                
            else:
                error_msg = stderr.decode('utf-8') if stderr else "خطای نامشخص"
                logger.error(f"FFmpeg error: {error_msg}")
                await processing_msg.edit_text(
                    "❌ **خطا در پردازش ویدیو**\n\n"
                    "لطفاً دوباره تلاش کنید یا از /start استفاده کنید"
                )
                
        except Exception as ffmpeg_error:
            logger.error(f"FFmpeg execution error: {ffmpeg_error}")
            await processing_msg.edit_text(
                "❌ **خطا در پردازش**\n\n"
                "مشکلی در سرور رخ داده است. لطفاً دوباره تلاش کنید"
            )
            
    except Exception as e:
        logger.error(f"Error processing video: {e}")
        await update.message.reply_text("❌ خطا در پردازش ویدیو")
        
    finally:
        # Cleanup files
        try:
            if 'video_path' in locals() and os.path.exists(video_path):
                os.unlink(video_path)
            if 'output_path' in locals() and os.path.exists(output_path):
                os.unlink(output_path)
            # Clean up banner after processing
            if user_id in user_banners:
                banner_path = user_banners[user_id]
                if os.path.exists(banner_path):
                    os.unlink(banner_path)
                del user_banners[user_id]
        except Exception as cleanup_error:
            logger.error(f"Cleanup error: {cleanup_error}")

async def handle_wrong_content(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle wrong content type"""
    user_id = update.effective_user.id
    current_state = user_states.get(user_id, BotState.IDLE)
    
    if current_state == BotState.WAITING_BANNER:
        await update.message.reply_text(
            "❌ **لطفاً یک عکس (بنر) ارسال کنید**\n\n"
            "🔄 برای شروع مجدد از /start استفاده کنید"
        )
    elif current_state == BotState.WAITING_VIDEO:
        await update.message.reply_text(
            "❌ **لطفاً یک ویدیو ارسال کنید**\n\n"
            "🔄 برای شروع مجدد از /start استفاده کنید"
        )
    else:
        await update.message.reply_text(
            "❌ **نامشخص!**\n\n"
            "🚀 برای شروع از /start استفاده کنید"
        )

def setup_bot():
    """Setup and configure the bot"""
    print("🤖 Telegram Video Banner Bot Setup")
    print("=" * 40)
    
    config.bot_token = input("📱 Bot Token را وارد کنید: ").strip()
    config.owner_id = input("👤 Owner ID (عدد) را وارد کنید: ").strip()
    
    if not config.bot_token:
        print("❌ Bot Token الزامی است!")
        return False
    
    return True

def main() -> None:
    """Main function to run the bot"""
    if not setup_bot():
        return
    
    print("\n🚀 Bot is starting...")
    
    # Create application
    application = Application.builder().token(config.bot_token).build()
    
    # Add handlers
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CallbackQueryHandler(button_callback))
    application.add_handler(MessageHandler(filters.PHOTO, handle_banner))
    application.add_handler(MessageHandler(filters.VIDEO, handle_video))
    application.add_handler(MessageHandler(~filters.COMMAND, handle_wrong_content))
    
    print("✅ Bot is running...")
    print("Press Ctrl+C to stop")
    
    # Run the bot
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()
