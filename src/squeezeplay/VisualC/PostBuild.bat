REM This batch executes after jive.exe has compiled.
REM command line arguments:
REM %1 = configuration name (Debug or Release)

REM Copy all the script files into the target directory
@echo on
cd..
cd..

md %1\lua
md %1\lua\applets
xcopy squeezeplay\share\applets\*.* %1\lua\applets\*.* /S/Y
xcopy squeezeplay_desktop\share\applets\*.* %1\lua\applets\*.* /S/Y
xcopy squeezeplay_contrib\share\applets\*.* %1\lua\applets\*.* /S/Y

md %1\lua\jive
xcopy squeezeplay\share\jive\*.* %1\lua\jive\*.* /S/Y
REM xcopy jive\rsc\jiveapp.png %1\lua\jive\*.* /S/Y


md %1\lua\loop
xcopy loop-2.2-alpha\loop\*.* %1\lua\loop\*.* /S/Y

xcopy luasocket-2.0.2\src\socket.lua %1\lua /Y
xcopy luasocket-2.0.2\src\ltn12.lua %1\lua /Y
xcopy luasocket-2.0.2\src\mime.lua %1\lua /Y
REM xcopy lualogging-1.1.2\src\logging\logging.lua %1\lua /Y

md %1\lua\socket
xcopy luasocket-2.0.2\src\ftp.lua %1\lua\socket /Y
xcopy luasocket-2.0.2\src\http.lua %1\lua\socket /Y
xcopy luasocket-2.0.2\src\smtp.lua %1\lua\socket /Y
xcopy luasocket-2.0.2\src\tp.lua %1\lua\socket /Y
xcopy luasocket-2.0.2\src\url.lua %1\lua\socket /Y

md %1\lua\lxp
xcopy luaexpat-1.0.2\src\lxp\lom.lua %1\lua\lxp /Y

md %1\fonts
xcopy dejavu-fonts-ttf-2.37\ttf\DejaVuSansCondensed.ttf %1\fonts /Y
xcopy dejavu-fonts-ttf-2.37\ttf\DejaVuSansCondensed-Bold.ttf %1\fonts /Y
ren %1\fonts\DejaVuSansCondensed.ttf FreeSans.ttf
ren %1\fonts\DejaVuSansCondensed-Bold.ttf FreeSansBold.ttf

xcopy SDL_image-1.2.5\VisualC\graphics\lib\*.dll %1 /Y
