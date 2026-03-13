@echo off
REM sync.bat — локальный запуск синхронизации (Windows)
REM Использование: sync.bat [путь к корню репо]

setlocal

set "SCRIPT_DIR=%~dp0"
if "%~1"=="" (
    set "REPO_ROOT=%SCRIPT_DIR%"
) else (
    set "REPO_ROOT=%~1"
)

echo === sync_index ===
echo Корень репо: %REPO_ROOT%
echo.

REM Проверяем python
where python >nul 2>&1
if errorlevel 1 (
    where python3 >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] python / python3 не найден. Установите Python 3.9+
        exit /b 1
    )
    set "PYTHON=python3"
) else (
    set "PYTHON=python"
)

%PYTHON% "%SCRIPT_DIR%scripts\sync_index.py" "%REPO_ROOT%"
