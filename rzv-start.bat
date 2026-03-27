@echo off
:: Root Zero Vault — Windows Startup Script
:: Run this instead of rzv up directly

set RZV_HOME=%USERPROFILE%\.rzv
set RZV_BIN=%LOCALAPPDATA%\RootZeroVault\rsbis-service.exe

:: Load store key
for /f "delims=" %%i in ('type "%RZV_HOME%\store.key"') do set RSBIS_STORE_KEY=%%i

echo [RZV] Starting Root Zero Vault...
echo [RZV] Home: %RZV_HOME%
echo [RZV] Console: http://localhost:8443/console/
echo.

rzv up --home "%RZV_HOME%" --bin "%RZV_BIN%"
