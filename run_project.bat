@echo off
REM =====================================================================
REM FILE        : run_project.bat
REM WHAT IT DOES: Starts the whole Pharmacy Inventory project with one double-click:
REM                 1. checks that Python and Node.js are installed
REM                 2. creates backend\.env (your MySQL login) on the first run
REM                 3. optionally rebuilds the MySQL database with the sample data
REM                 4. installs the Python and npm packages on the first run
REM                 5. starts the backend (FastAPI, port 8000) and the website
REM                    (React, port 5173), each in its own window, and opens the
REM                    website in your browser
REM USAGE       : run_project.bat          start everything
REM               run_project.bat db       rebuild the database first, then start everything
REM               run_project.bat stop     close the backend and website windows
REM DEPENDS ON  : MySQL 8 already running on this computer, Python 3.10 or newer,
REM               Node.js 20 or newer, backend\requirements.txt, frontend\package.json,
REM               database\run_all.sql
REM USED BY     : you (double-click it, or run it from a terminal)
REM OPTIONAL    : set NO_BROWSER=1 to skip opening the browser, NO_PAUSE=1 to skip the
REM               final "press any key" (useful when another script calls this file)
REM =====================================================================

REM Keep every variable inside this script, and enable the command extensions we use.
setlocal EnableExtensions
REM Work from the folder this file lives in, so the relative paths below always match.
cd /d "%~dp0"
title Pharmacy Inventory - launcher

REM "run_project.bat stop" only closes the two windows and ends.
if /i "%~1"=="stop" goto :stop

echo.
REM The & sign must be written as ^& in an echo line, otherwise batch treats it as "run another command".
echo ===== Pharmacy Inventory ^& Expiry Management System =====
echo.

REM ---------------------------------------------------------------------
REM STEP 1 - are the needed programs installed?
REM "where" looks for a program on the PATH; errorlevel 1 means "not found".
REM ---------------------------------------------------------------------
where python >nul 2>nul
if errorlevel 1 goto :no_python
where node >nul 2>nul
if errorlevel 1 goto :no_node
where npm >nul 2>nul
if errorlevel 1 goto :no_node
echo [1/5] Python and Node.js found.

REM ---------------------------------------------------------------------
REM STEP 2 - backend\.env holds the database login.
REM First run: copy the template, let the user type the MySQL password in Notepad.
REM ---------------------------------------------------------------------
if exist "backend\.env" goto :env_ready
copy "backend\.env.example" "backend\.env" >nul
echo.
echo First run: the file backend\.env was created.
echo Notepad opens now. Type your MySQL password after DB_PASSWORD= then save and close Notepad.
start /wait notepad "backend\.env"
set "ASK_DB=1"
:env_ready

REM Default values, then read backend\.env on top of them.
REM "eol=#" skips comment lines, "delims==" splits each line at the first = sign.
set "DB_HOST=localhost"
set "DB_PORT=3306"
set "DB_USER=root"
set "DB_PASSWORD="
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("backend\.env") do set "%%A=%%B"
echo [2/5] Database login read from backend\.env  user=%DB_USER%  host=%DB_HOST%  port=%DB_PORT%

REM ---------------------------------------------------------------------
REM STEP 3 - the database (only on the first run, or with: run_project.bat db)
REM ---------------------------------------------------------------------
if /i "%~1"=="db" set "ASK_DB=1"
if defined ASK_DB call :database
if not defined ASK_DB echo [3/5] Database step skipped. Use run_project.bat db to rebuild it.

REM ---------------------------------------------------------------------
REM STEP 4 - install the packages (first run only)
REM ---------------------------------------------------------------------
if exist "backend\venv\Scripts\python.exe" goto :venv_ready
echo [4/5] First run: creating the Python environment. This takes a minute ...
python -m venv "backend\venv"
if errorlevel 1 goto :fail
"backend\venv\Scripts\python.exe" -m pip install --disable-pip-version-check -r "backend\requirements.txt"
if errorlevel 1 goto :fail
:venv_ready

if exist "frontend\node_modules" goto :npm_ready
echo [4/5] First run: installing the website packages. This takes a minute ...
call npm --prefix "frontend" install --no-audit --no-fund
if errorlevel 1 goto :fail
:npm_ready
echo [4/5] Packages are ready.

REM ---------------------------------------------------------------------
REM STEP 5 - start the backend and the website, each in its own window.
REM A port that already answers is left alone (the project is probably running).
REM ---------------------------------------------------------------------
set "API_UP="
netstat -ano | findstr /r /c:":8000 .*LISTENING" >nul && set "API_UP=1"
set "WEB_UP="
netstat -ano | findstr /r /c:":5173 .*LISTENING" >nul && set "WEB_UP=1"

if defined API_UP goto :api_running
start "Pharmacy API" /d "%~dp0backend" cmd /k "venv\Scripts\python.exe -m uvicorn main:app --reload"
goto :api_started
:api_running
echo The backend already runs on port 8000 - leaving it as it is.
:api_started

if defined WEB_UP goto :web_running
start "Pharmacy website" /d "%~dp0frontend" cmd /k "npm run dev"
goto :web_started
:web_running
echo The website already runs on port 5173 - leaving it as it is.
:web_started

REM Wait up to 40 seconds until the website answers. "ping -n 2" is a 1-second pause.
echo [5/5] Starting the backend and the website ...
set /a TRIES=0
:wait_web
powershell -NoProfile -Command "try { $null = Invoke-WebRequest -Uri http://127.0.0.1:5173 -UseBasicParsing -TimeoutSec 2; exit 0 } catch { exit 1 }" >nul 2>nul
if not errorlevel 1 goto :web_ready
set /a TRIES+=1
if %TRIES% geq 40 goto :web_slow
ping -n 2 127.0.0.1 >nul
goto :wait_web

:web_ready
REM Ask the backend /health URL: it also proves that MySQL can be reached.
powershell -NoProfile -Command "try { $r = Invoke-RestMethod -Uri http://127.0.0.1:8000/health -TimeoutSec 5; if ($r.status -eq 'ok') { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>nul
if errorlevel 1 goto :api_problem
echo.
echo Everything is running:
echo    Website : http://127.0.0.1:5173
echo    Backend : http://127.0.0.1:8000/docs
echo    MySQL   : connected
goto :open_browser

:api_problem
echo.
echo The website is running, but the backend could not reach MySQL.
echo    - Is MySQL running on this computer?
echo    - Are DB_USER and DB_PASSWORD in backend\.env correct?
echo    - Was the database built? Run:  run_project.bat db
echo Look at the "Pharmacy API" window for the exact error.
goto :open_browser

:web_slow
echo.
echo The website did not answer within 40 seconds. Look at the "Pharmacy website" window.
goto :finish

:open_browser
if not defined NO_BROWSER start "" "http://127.0.0.1:5173"
echo.
echo You can close this window. The servers keep running in their own windows.
echo To stop them:  run_project.bat stop
goto :finish

REM ---------------------------------------------------------------------
REM Subroutine - rebuild the database with database\run_all.sql
REM ---------------------------------------------------------------------
:database
echo.
echo ---- MySQL database ----
echo This DELETES the database pharmacy_db if it exists and rebuilds it with the sample data.
set "CONFIRM="
set /p "CONFIRM=Type YES to continue, or just press Enter to skip: "
if /i not "%CONFIRM%"=="YES" goto :database_skipped

REM Find mysql.exe: first on the PATH, then in the normal install folders.
set "MYSQL_EXE="
for /f "delims=" %%M in ('where mysql 2^>nul') do if not defined MYSQL_EXE set "MYSQL_EXE=%%M"
if not defined MYSQL_EXE if exist "%ProgramFiles%\MySQL\MySQL Server 8.4\bin\mysql.exe" set "MYSQL_EXE=%ProgramFiles%\MySQL\MySQL Server 8.4\bin\mysql.exe"
if not defined MYSQL_EXE if exist "%ProgramFiles%\MySQL\MySQL Server 8.0\bin\mysql.exe" set "MYSQL_EXE=%ProgramFiles%\MySQL\MySQL Server 8.0\bin\mysql.exe"
if not defined MYSQL_EXE goto :no_mysql_client

REM The password comes from backend\.env through the MYSQL_PWD variable, so it never
REM appears on the command line. The variable disappears when this script ends.
set "MYSQL_PWD=%DB_PASSWORD%"
REM run_all.sql uses SOURCE with relative paths, so it must run from the database folder.
pushd "%~dp0database"
REM ">nul" hides the long list of tables, views and triggers that run_all.sql prints; error messages still show.
"%MYSQL_EXE%" -h %DB_HOST% -P %DB_PORT% -u %DB_USER% < run_all.sql >nul
if errorlevel 1 goto :database_failed
popd
echo [3/5] Database rebuilt with the sample data.
exit /b 0

:database_failed
popd
echo.
echo The database could not be rebuilt. Check DB_USER and DB_PASSWORD in backend\.env and that MySQL is running.
goto :fail

:no_mysql_client
echo.
echo mysql.exe was not found. Add the MySQL bin folder to PATH, or run database\run_all.sql yourself.
goto :fail

:database_skipped
echo [3/5] Database step skipped.
exit /b 0

REM ---------------------------------------------------------------------
REM "run_project.bat stop" - close both windows and free the two ports
REM ---------------------------------------------------------------------
:stop
echo Stopping the backend and the website ...
REM Close the two windows by their title (/t also ends the programs started inside them).
taskkill /fi "WINDOWTITLE eq Pharmacy API*" /t /f >nul 2>nul
taskkill /fi "WINDOWTITLE eq Pharmacy website*" /t /f >nul 2>nul
REM Safety net: free port 8000 and port 5173. For each port we find the program that owns it,
REM and stop it together with its helper processes. This matters for the backend: uvicorn
REM --reload starts a worker that keeps the port open even after its parent is gone. Such a
REM worker is found through its parent id, so no other Python program is touched.
powershell -NoProfile -Command "foreach ($p in 8000,5173) { $o = (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess; if ($o) { Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $o -or $_.CommandLine -match ('parent_pid=' + $o + '[,)]') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Stop-Process -Id $o -Force -ErrorAction SilentlyContinue } }" >nul 2>nul
echo Stopped.
goto :end

REM ---------------------------------------------------------------------
REM Error messages
REM ---------------------------------------------------------------------
:no_python
echo [!] Python was not found. Install Python 3.10 or newer from https://www.python.org/downloads/
echo     and tick "Add Python to PATH" in the installer.
goto :fail

:no_node
echo [!] Node.js was not found. Install Node.js 20 or newer from https://nodejs.org/
goto :fail

:fail
echo.
echo The launcher stopped because of the problem above.
if not defined NO_PAUSE pause
exit /b 1

:finish
:end
if not defined NO_PAUSE pause
endlocal
