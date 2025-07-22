#!/usr/bin/env python3
import os
import logging
import asyncio
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
import subprocess
import tempfile

# Configure logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

class VideoLogoBotConfig:
    def __init__(self):
        self.bot_token = ""
        self.owner_id = ""
        self.log_channel_id = ""
        self.logo_path = "logo.png"  # Your logo file path

config = VideoLogoBotConfig()

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Start command handler"""
    welcome_message = """
🎬 **Telegram Video Logo Bot**

سلام! من ربات اضافه کردن لوگو به ویدیو هستم.

📹 **چطور کار می‌کنم:**
1️⃣ ویدیوتون رو بفرستید
2️⃣ لوگو رو در ثانیه اول اضافه می‌کنم
3️⃣ ویدیو با همون کیفیت و حجم برمی‌گردونم

🚀 **شروع کنید!**
"""
    await update.message.reply_text(welcome_message)

async def process_video(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Process video and add logo"""
    try:
        # Send processing message
        processing_msg = await update.message.reply_text("🔄 در حال پردازش ویدیو...")
        
        # Download video
        video_file = await context.bot.get_file(update.message.video.file_id)
        
        # Create temporary files
        with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as input_file:
            await video_file.download_to_drive(input_file.name)
            input_path = input_file.name
            
        with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as output_file:
            output_path = output_file.name
            
        # FFmpeg command to add logo in first second
        ffmpeg_cmd = [
            'ffmpeg', '-i', input_path,
            '-i', config.logo_path,
            '-filter_complex',
            '[0:v][1:v] overlay=10:10:enable=\'between(t,0,1)\' [out]',
            '-map', '[out]',
            '-map', '0:a?',
            '-c:a', 'copy',
            '-c:v', 'libx264',
            '-preset', 'fast',
            '-crf', '23',
            output_path,
            '-y'
        ]
        
        # Execute FFmpeg
        process = subprocess.run(ffmpeg_cmd, capture_output=True, text=True)
        
        if process.returncode == 0:
            # Send processed video
            await processing_msg.edit_text("✅ ویدیو آماده! در حال ارسال...")
            
            with open(output_path, 'rb') as video_file:
                await update.message.reply_video(
                    video=video_file,
                    caption="✨ ویدیو با لوگو آماده شد!\n\n@YourChannelName"
                )
            
            await processing_msg.delete()
        else:
            await processing_msg.edit_text("❌ خطا در پردازش ویدیو")
            
        # Cleanup
        os.unlink(input_path)
        os.unlink(output_path)
        
    except Exception as e:
        logger.error(f"Error processing video: {e}")
        await update.message.reply_text("❌ خطا در پردازش ویدیو")

def setup_bot():
    """Setup and configure the bot"""
    # Get configuration from user
    print("🤖 Telegram Video Logo Bot Setup")
    print("=" * 40)
    
    config.bot_token = input("📱 Bot Token را وارد کنید: ").strip()
    config.owner_id = input("👤 Owner ID (عدد) را وارد کنید: ").strip()
    config.log_channel_id = input("📢 Log Channel ID (اختیاری): ").strip()
    
    # Check if logo exists
    if not os.path.exists(config.logo_path):
        print(f"⚠️  فایل لوگو ({config.logo_path}) یافت نشد!")
        logo_path = input("📸 مسیر فایل لوگو را وارد کنید: ").strip()
        if logo_path and os.path.exists(logo_path):
            config.logo_path = logo_path
        else:
            print("❌ فایل لوگو یافت نشد. لطفاً logo.png را در همین پوشه قرار دهید.")
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
    application.add_handler(MessageHandler(filters.VIDEO, process_video))
    
    print("✅ Bot is running...")
    print("Press Ctrl+C to stop")
    
    # Run the bot
    application.run_polling()

if __name__ == '__main__':
    main()
