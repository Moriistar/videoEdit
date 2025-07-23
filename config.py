"""
Configuration module for Ultra Fast Video Banner Bot
تنظیمات ربات فوق سریع اضافه کردن بنر به ویدیو
"""

import os
from pathlib import Path
from typing import Optional

class BotConfig:
    """Bot configuration class"""
    
    def __init__(self):
        # Bot API Configuration
        self.BOT_TOKEN: str = os.getenv('BOT_TOKEN', '')
        self.OWNER_ID: Optional[int] = self._get_int_env('OWNER_ID')
        
        # User Client Configuration (Optional)
        self.USE_USER_CLIENT: bool = os.getenv('USE_USER_CLIENT', 'true').lower() == 'true'
        self.API_ID: Optional[int] = self._get_int_env('API_ID')
        self.API_HASH: str = os.getenv('API_HASH', '')
        self.PHONE_NUMBER: str = os.getenv('PHONE_NUMBER', '')
        self.SESSION_NAME: str = os.getenv('SESSION_NAME', 'video_bot_session')
        
        # File Configuration
        self.MAX_FILE_SIZE: int = self._get_int_env('MAX_FILE_SIZE', 2 * 1024 * 1024 * 1024)  # 2GB
        self.TEMP_DIR: str = os.getenv('TEMP_DIR', 'temp')
        
        # Performance Configuration
        self.MAX_WORKERS: int = self._get_int_env('MAX_WORKERS', 4)
        self.PROCESSING_TIMEOUT: int = self._get_int_env('PROCESSING_TIMEOUT', 600)  # 10 minutes
        
        # FFmpeg Configuration
        self.FFMPEG_PRESET: str = os.getenv('FFMPEG_PRESET', 'ultrafast')
        self.FFMPEG_CRF: int = self._get_int_env('FFMPEG_CRF', 23)
        self.FFMPEG_MAXRATE: str = os.getenv('FFMPEG_MAXRATE', '200M')
        
        # Logging Configuration
        self.LOG_LEVEL: str = os.getenv('LOG_LEVEL', 'INFO')
        self.LOG_FILE: str = os.getenv('LOG_FILE', 'logs/bot.log')
        
        # Validate required settings
        self._validate_config()
    
    def _get_int_env(self, key: str, default: Optional[int] = None) -> Optional[int]:
        """Get integer environment variable"""
        value = os.getenv(key)
        if value is None:
            return default
        try:
            return int(value)
        except ValueError:
            return default
    
    def _validate_config(self):
        """Validate configuration"""
        if not self.BOT_TOKEN:
            raise ValueError("BOT_TOKEN is required")
        
        if self.USE_USER_CLIENT:
            if not all([self.API_ID, self.API_HASH, self.PHONE_NUMBER]):
                print("⚠️  User Client disabled: Missing API_ID, API_HASH, or PHONE_NUMBER")
                self.USE_USER_CLIENT = False
        
        # Create directories
        Path(self.TEMP_DIR).mkdir(exist_ok=True)
        Path(os.path.dirname(self.LOG_FILE)).mkdir(exist_ok=True)
    
    def get_user_client_config(self) -> dict:
        """Get user client configuration"""
        return {
            'session_name': self.SESSION_NAME,
            'api_id': self.API_ID,
            'api_hash': self.API_HASH,
            'phone_number': self.PHONE_NUMBER
        }
    
    def get_ffmpeg_config(self) -> dict:
        """Get FFmpeg configuration"""
        return {
            'preset': self.FFMPEG_PRESET,
            'crf': self.FFMPEG_CRF,
            'maxrate': self.FFMPEG_MAXRATE
        }

# Environment setup helper
def setup_environment():
    """Setup environment variables interactively"""
    print("🚀 Ultra Fast Video Banner Bot - Configuration Setup")
    print("=" * 60)
    
    # Bot Token
    bot_token = input("📱 Bot Token: ").strip()
    if not bot_token:
        print("❌ Bot Token is required!")
        return False
    
    # Owner ID (optional)
    owner_id = input("👤 Owner ID (optional): ").strip()
    
    # User Client setup
    use_user_client = input("🔄 Enable User Client? (y/n) [y]: ").strip().lower()
    if use_user_client in ['', 'y', 'yes']:
        print("\n🔐 User Client Setup (for large files):")
        api_id = input("🔑 API ID (from my.telegram.org): ").strip()
        api_hash = input("🔐 API Hash: ").strip()
        phone_number = input("📞 Phone Number (+98912...): ").strip()
        
        if not all([api_id, api_hash, phone_number]):
            print("⚠️  User Client will be disabled (missing credentials)")
            use_user_client = 'n'
    else:
        api_id = api_hash = phone_number = ""
    
    # Create .env file
    env_content = f"""# Ultra Fast Video Banner Bot Configuration
# Bot API Configuration
BOT_TOKEN={bot_token}
OWNER_ID={owner_id}

# User Client Configuration (Optional)
USE_USER_CLIENT={use_user_client in ['', 'y', 'yes']}
API_ID={api_id}
API_HASH={api_hash}
PHONE_NUMBER={phone_number}
SESSION_NAME=video_bot_session

# File Configuration
MAX_FILE_SIZE=2147483648  # 2GB
TEMP_DIR=temp

# Performance Configuration
MAX_WORKERS=4
PROCESSING_TIMEOUT=600

# FFmpeg Configuration
FFMPEG_PRESET=ultrafast
FFMPEG_CRF=23
FFMPEG_MAXRATE=200M

# Logging Configuration
LOG_LEVEL=INFO
LOG_FILE=logs/bot.log
"""
    
    with open('.env', 'w', encoding='utf-8') as f:
        f.write(env_content)
    
    print("\n✅ Configuration saved to .env file!")
    print("🚀 You can now run: python main.py")
    return True

if __name__ == '__main__':
    setup_environment()
