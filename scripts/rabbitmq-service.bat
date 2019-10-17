@echo off
REM  The contents of this file are subject to the Mozilla Public License
REM  Version 1.1 (the "License"); you may not use this file except in
REM  compliance with the License. You may obtain a copy of the License
REM  at https://www.mozilla.org/MPL/
REM
REM  Software distributed under the License is distributed on an "AS IS"
REM  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
REM  the License for the specific language governing rights and
REM  limitations under the License.
REM
REM  The Original Code is RabbitMQ.
REM
REM  The Initial Developer of the Original Code is GoPivotal, Inc.
REM  Copyright (c) 2007-2019 Pivotal Software, Inc.  All rights reserved.
REM

setlocal

rem Preserve values that might contain exclamation marks before
rem enabling delayed expansion
set TN0=%~n0
set TDP0=%~dp0
set CONF_SCRIPT_DIR=%~dp0
set P1=%1
setlocal enabledelayedexpansion
setlocal enableextensions

if ERRORLEVEL 1 (
    echo "Failed to enable command extensions!"
    exit /B 1
)

REM Get default settings with user overrides for (RABBITMQ_)<var_name>
REM Non-empty defaults should be set in rabbitmq-env
call "%TDP0%\rabbitmq-env.bat" %~n0

REM Check for the short names here too
if "!RABBITMQ_USE_LONGNAME!"=="true" (
    set RABBITMQ_NAME_TYPE=-name
    set NAMETYPE=longnames
) else (
    if "!USE_LONGNAME!"=="true" (
        set RABBITMQ_USE_LONGNAME=true
        set RABBITMQ_NAME_TYPE=-name
        set NAMETYPE=longnames
    ) else (
        set RABBITMQ_USE_LONGNAME=false
        set RABBITMQ_NAME_TYPE=-sname
        set NAMETYPE=shortnames
    )
)

REM [ "x" = "x$RABBITMQ_NODENAME" ] && RABBITMQ_NODENAME=${NODENAME}
if "!RABBITMQ_NODENAME!"=="" (
    if "!NODENAME!"=="" (
        REM We use Erlang to query the local hostname because
        REM !COMPUTERNAME! and Erlang may return different results.
        REM Start erl with -sname to make sure epmd is started.
        call "%ERLANG_HOME%\bin\erl.exe" -A0 -noinput -boot start_clean -sname rabbit-prelaunch-epmd -eval "init:stop()." >nul 2>&1
        for /f "delims=" %%F in ('call "%ERLANG_HOME%\bin\erl.exe" -A0 -noinput -boot start_clean -eval "net_kernel:start([list_to_atom(""rabbit-gethostname-"" ++ os:getpid()), %NAMETYPE%]), [_, H] = string:tokens(atom_to_list(node()), ""@""), io:format(""~s~n"", [H]), init:stop()."') do @set HOSTNAME=%%F
        set RABBITMQ_NODENAME=rabbit@!HOSTNAME!
        set HOSTNAME=
    ) else (
        set RABBITMQ_NODENAME=!NODENAME!
    )
)
set NAMETYPE=

set STARVAR=
shift
:loop1
if "%1"=="" goto after_loop
	set STARVAR=%STARVAR% %1
	shift
goto loop1
:after_loop

if "!ERLANG_SERVICE_MANAGER_PATH!"=="" (
    if not exist "!ERLANG_HOME!\bin\erl.exe" (
        echo.
        echo ******************************
        echo ERLANG_HOME not set correctly.
        echo ******************************
        echo.
        echo Please either set ERLANG_HOME to point to your Erlang installation or place the
        echo RabbitMQ server distribution in the Erlang lib folder.
        echo.
        exit /B
    )
    for /f "delims=" %%i in ('dir /ad/b "!ERLANG_HOME!"') do if exist "!ERLANG_HOME!\%%i\bin\erlsrv.exe" (
        set ERLANG_SERVICE_MANAGER_PATH=!ERLANG_HOME!\%%i\bin
    )
)

set CONSOLE_FLAG=
set CONSOLE_LOG_VALID=
for %%i in (new reuse) do if "%%i" == "!RABBITMQ_CONSOLE_LOG!" set CONSOLE_LOG_VALID=TRUE
if "!CONSOLE_LOG_VALID!" == "TRUE" (
    set CONSOLE_FLAG=-debugtype !RABBITMQ_CONSOLE_LOG!
)

rem *** End of configuration ***

if not exist "!ERLANG_SERVICE_MANAGER_PATH!\erlsrv.exe" (
    echo.
    echo **********************************************
    echo ERLANG_SERVICE_MANAGER_PATH not set correctly.
    echo **********************************************
    echo.
    echo "!ERLANG_SERVICE_MANAGER_PATH!\erlsrv.exe" not found
    echo Please set ERLANG_SERVICE_MANAGER_PATH to the folder containing "erlsrv.exe".
    echo.
    exit /B 1
)

if "!P1!" == "install" goto INSTALL_SERVICE
for %%i in (start stop) do if "%%i" == "!P1!" goto START_STOP_SERVICE
for %%i in (disable enable list remove) do if "%%i" == "!P1!" goto MODIFY_SERVICE

echo.
echo *********************
echo Service control usage
echo *********************
echo.
echo !TN0! help    - Display this help
echo !TN0! install - Install the !RABBITMQ_SERVICENAME! service
echo !TN0! remove  - Remove the !RABBITMQ_SERVICENAME! service
echo.
echo The following actions can also be accomplished by using
echo Windows Services Management Console (services.msc):
echo.
echo !TN0! start   - Start the !RABBITMQ_SERVICENAME! service
echo !TN0! stop    - Stop the !RABBITMQ_SERVICENAME! service
echo !TN0! disable - Disable the !RABBITMQ_SERVICENAME! service
echo !TN0! enable  - Enable the !RABBITMQ_SERVICENAME! service
echo.
exit /B


:INSTALL_SERVICE

if not exist "!RABBITMQ_BASE!" (
    echo Creating base directory !RABBITMQ_BASE! & mkdir "!RABBITMQ_BASE!"
)

"!ERLANG_SERVICE_MANAGER_PATH!\erlsrv" list !RABBITMQ_SERVICENAME! 2>NUL 1>NUL
if errorlevel 1 (
    "!ERLANG_SERVICE_MANAGER_PATH!\erlsrv" add !RABBITMQ_SERVICENAME! -internalservicename !RABBITMQ_SERVICENAME!
) else (
    echo !RABBITMQ_SERVICENAME! service is already present - only updating service parameters
)

set RABBITMQ_DEFAULT_ALLOC_ARGS=+MBas ageffcbf +MHas ageffcbf +MBlmbcs 512 +MHlmbcs 512 +MMmcs 30

set RABBITMQ_START_RABBIT=
if "!RABBITMQ_NODE_ONLY!"=="" (
    set RABBITMQ_START_RABBIT=-s "!RABBITMQ_BOOT_MODULE!" boot
)

if "!RABBITMQ_IO_THREAD_POOL_SIZE!"=="" (
    set RABBITMQ_IO_THREAD_POOL_SIZE=64
)

if "!RABBITMQ_SERVICE_RESTART!"=="" (
    set RABBITMQ_SERVICE_RESTART=restart
)

set ENV_OK=true
CALL :check_not_empty "RABBITMQ_BOOT_MODULE" !RABBITMQ_BOOT_MODULE!
CALL :check_not_empty "RABBITMQ_NAME_TYPE" !RABBITMQ_NAME_TYPE!
CALL :check_not_empty "RABBITMQ_NODENAME" !RABBITMQ_NODENAME!

if "!ENV_OK!"=="false" (
    EXIT /b 78
)

set ERLANG_SERVICE_ARGUMENTS= ^
!RABBITMQ_START_RABBIT! ^
-boot "!SASL_BOOT_FILE!" ^
+W w ^
+A "!RABBITMQ_IO_THREAD_POOL_SIZE!" ^
!RABBITMQ_DEFAULT_ALLOC_ARGS! ^
!RABBITMQ_SERVER_ERL_ARGS! ^
!RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS! ^
-os_mon start_cpu_sup false ^
-os_mon start_disksup false ^
-os_mon start_memsup false ^
!RABBITMQ_SERVER_START_ARGS! ^
!STARVAR!

set ERLANG_SERVICE_ARGUMENTS=!ERLANG_SERVICE_ARGUMENTS:\=\\!
set ERLANG_SERVICE_ARGUMENTS=!ERLANG_SERVICE_ARGUMENTS:"=\"!

"!ERLANG_SERVICE_MANAGER_PATH!\erlsrv" set !RABBITMQ_SERVICENAME! ^
-onfail !RABBITMQ_SERVICE_RESTART! ^
-machine "!ERLANG_SERVICE_MANAGER_PATH!\erl.exe" ^
-env ERL_LIBS="!ERL_LIBS!" ^
-env ERL_MAX_ETS_TABLES="!ERL_MAX_ETS_TABLES!" ^
-env ERL_MAX_PORTS="!ERL_MAX_PORTS!" ^
-workdir "!RABBITMQ_BASE!" ^
-stopaction "rabbit:stop_and_halt()." ^
!RABBITMQ_NAME_TYPE! !RABBITMQ_NODENAME! ^
!CONSOLE_FLAG! ^
-comment "Multi-protocol open source messaging broker" ^
-args "!ERLANG_SERVICE_ARGUMENTS!" > NUL

if ERRORLEVEL 1 (
    EXIT /B 1
)
goto END


:MODIFY_SERVICE

"!ERLANG_SERVICE_MANAGER_PATH!\erlsrv" !P1! !RABBITMQ_SERVICENAME!
if ERRORLEVEL 1 (
    EXIT /B 1
)
goto END


:START_STOP_SERVICE

REM start and stop via erlsrv reports no error message. Using net instead
net !P1! !RABBITMQ_SERVICENAME!
if ERRORLEVEL 1 (
    EXIT /B 1
)
goto END

:END

EXIT /B 0

:check_not_empty
if "%~2"=="" (
    ECHO "Error: ENV variable should be defined: %1. Please check rabbitmq-env, rabbitmq-default, and !RABBITMQ_CONF_ENV_FILE! script files. Check also your Environment Variables settings"
    set ENV_OK=false
    EXIT /B 78
    )
EXIT /B 0

endlocal
endlocal
endlocal
