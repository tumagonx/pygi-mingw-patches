#!/bin/sh

set -e

if [ "$1" == "" ] || [ "$2" == "" ]; then 
echo "Usage: ${0##*/} [bits: 32|64] [msvcrt: 90|100] [install prefix] [sources prefix]"
exit
fi

if [ "$NUMBER_OF_PROCESSORS" != "" ]; then export PJOBS=-j$NUMBER_OF_PROCESSORS; else export PJOBS=""; fi
export CPUARCH=$1

if [ "$3" == "" ]; then 
export IPATH=/local
else
export PATH=$3/bin:$PATH
export IPATH=$3
fi

if [ "$1" == "64" ]; then export MULTILIB=$1; fi
if [ -f /opt/bin/mt.exe ]; then export MSSDK=1; fi
if [ "$MULTILIB" == "64" ]; then
    if [ "$PROCESSOR_ARCHITEW6432" == "AMD64" ] || [ "$PROCESSOR_ARCHITECTURE" == "AMD64" ]; then
        triplet="--host=x86_64-w64-mingw32 --build=x86_64-w64-mingw32"
        alias configure="configure $triplet --prefix=$IPATH"
        export INTROSPECT=--enable-introspection=yes
        export GTKDOC=--enable-gtk-doc
    else
        triplet="--host=x86_64-w64-mingw32"
        alias configure="configure $triplet --prefix=$IPATH"
        CROSSX=1
        export INTROSPECT=--enable-introspection=no
        export GTKDOC=--disable-gtk-doc
    fi
    RCFLAGS="-F pe-x86-64"
    ASFLAGS="--64 -m i386:x86-64"
    DLLTOOLFLAGS="--as-flags=--64 -m i386:x86-64"
    source setgcc gcc48
else
    alias configure="configure --prefix=$IPATH"
    export INTROSPECT=--enable-introspection=yes
    source setgcc gcc48
fi

if [ "$2" == "90" ];then alias manifest='cmd //c /opt/bin/mtall90.bat'; else alias manifest=""; fi
if [ "$2" != "0" ]; then
RTVER="-m$1 -vcr$2"
else
RTVER="-m$1"
fi

export PKG_CONFIG_PATH=$IPATH/lib/pkgconfig:$IPATH/share/pkgconfig
export CPPFLAGS=-I$IPATH/include
if [ "$MULTILIB" != 64 ]; then
export LDFLAGS="$RTVER -Wl,-s -Wl,--large-address-aware  -L$IPATH/lib"
export CC="gcc $RTVER -fno-unwind-tables -fno-asynchronous-unwind-tables"
export CXX="g++ $RTVER -fno-unwind-tables -fno-asynchronous-unwind-tables"
export CFLAGS="$RTVER -Os -pipe  -mno-sse2 -mno-avx -fno-lto -D_FILE_OFFSET_BITS=64"
else
export LDFLAGS="$RTVER -Wl,-s -L$IPATH/lib"
export CC="gcc $RTVER"
export CXX="g++ $RTVER"
export CFLAGS="$RTVER -Os -pipe -mno-sse3 -mno-avx -fno-lto -D_FILE_OFFSET_BITS=64"
fi
export CXXFLAGS=$CFLAGS
export MOZ_TOOLS=/opt/bin
unset LUA_PATH

if [ "$CROSSX" == "1" ]; then
    # static build exes with no dependencies
    # note that many libraries can't be build via cross compiling
    export GLIB_GENMARSHAL=/opt/bin/glib-genmarshal
    export GLIB_MKENUMS=/opt/bin/glib-mkenums
    export GLIB_COMPILE_SCHEMAS=/opt/bin/glib-compile-schemas
    export GLIB_COMPILE_RESOURCES=/opt/bin/glib-compile-resources
    export DBUS_BINDING_TOOL=/opt/bin/dbus-binding-tool
    export ORCC=/opt/bin/orcc
    export GTK_UPDATE_ICON_CACHE=/opt/bin/gtk-update-icon-cache 
    export GDK_PIXBUF_CSOURCE=/opt/bin/gdk-pixbuf-csource
else
    set +e
    rm $IPATH/bin/glib-genmarshal
    rm $IPATH/bin/glib-compile-resources
    rm $IPATH/bin/glib-compile-schemas
    set -e
    export GLIB_GENMARSHAL=$IPATH/bin/glib-genmarshal
    export GLIB_MKENUMS=$IPATH/bin/glib-mkenums
    export GLIB_COMPILE_SCHEMAS=$IPATH/bin/glib-compile-schemas
    export GLIB_COMPILE_RESOURCES=$IPATH/bin/glib-compile-resources
    export DBUS_BINDING_TOOL=$IPATH/bin/dbus-binding-tool
    export ORCC=$IPATH/bin/orcc
    export GTK_UPDATE_ICON_CACHE=$IPATH/bin/gtk-update-icon-cache 
    export GDK_PIXBUF_CSOURCE=$IPATH/bin/gdk-pixbuf-csource
fi

if [ "$4" != "" ];then 
export SPATH=$4
else
export SPATH=/d/Sources
fi

:<<"XXX"

cd $SPATH/../Tarball/mingw-w64-v4.0.4/mingw-w64-libraries/winpthreads
configure --disable-static
make clean
make $PJOBS
manifest
make install
rm $IPATH/lib/*.la
rm $IPATH/include/pthread*.h

cd $SPATH/libstdc++/
set +e
rm -rdf build
rm $IPATH/lib/libstdc++.dll.a
set -e
mkdir build
cd build
../../../tarball/gcc-4.8.4/libstdc++-v3/configure --disable-multilib --enable-fully-dynamic-string CFLAGS="-Os -D_FILE_OFFSET_BITS=64" CXXFLAGS="-Os -D_FILE_OFFSET_BITS=64" CC="gcc $RTVER" CXX="g++ $RTVER"
make $PJOBS
cp src/.libs/libstdc++.dll.a $IPATH/lib/
cp src/.libs/libstdc++-6.dll $IPATH/bin/

cd $SPATH/zlib-1.2.8
make -f win32/Makefile.gcc clean
if [ "$MULTILIB" != 64 ]; then
make -f win32/Makefile.gcc $PJOBS CFLAGS="$CFLAGS -O2 -DASMV" libz.a
#this one is slightly faster on small data but way slower than vanilla on huge data
#nasm -f win32 match.asm -o match.o
jwasm -coff -8 -Fo match.o match686.asm
jwasm -coff -8 -Fo inffast.o inffast32.asm
ar cru libz.a match.o inffast.o
ranlib libz.a
fi
make -f win32/Makefile.gcc install $PJOBS INCLUDE_PATH=$IPATH/include BINARY_PATH=$IPATH/bin LIBRARY_PATH=$IPATH/lib
cd $SPATH/bzip2
make -f Makefile clean
make -f Makefile-libbz2_so $PJOBS  CFLAGS="$CFLAGS -O2"
cp bzlib.h $IPATH/include/
ar cru $IPATH/lib/libbz2.a bzlib.o blocksort.o compress.o crctable.o decompress.o huffman.o randtable.o
ranlib $IPATH/lib/libbz2.a
cd $SPATH/xz-5.2.1
configure --disable-shared --enable-threads=posix --enable-assume-ram=1024 --disable-nls
make clean
make $PJOBS
manifest
make install
make check
rm $IPATH/lib/*.la
$CC $LDFLAGS -shared -o $IPATH/bin/libzzz.dll -Wl,--out-implib,$IPATH/lib/libz.dll.a -Wl,--whole-archive $IPATH/lib/libz.a $IPATH/lib/liblzma.a $IPATH/lib/libbz2.a -Wl,--no-whole-archive
cp $IPATH/lib/libz.dll.a $IPATH/lib/liblzma.dll.a 
cp $IPATH/lib/libz.dll.a $IPATH/lib/libbz2.dll.a
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: zlib
Description: zlib compression library
Version: 1.2.8
Requires:
Libs: -L${libdir} -lz
Cflags: -I${includedir}'> $IPATH/lib/pkgconfig/zlib.pc
:<<"XXXX"
# usable but no use for webkit or cairo or anything for now
cd $SPATH/angle-chromium-2020/src
echo "Making libcommon..."
cd common
$CXX $CXXFLAGS -DNDEBUG -DNOMINMAX -DANGLE_DISABLE_TRACE -DANGLE_DISABLE_PERF -DCOMPONENT_BUILD -DUNICODE -D_UNICODE  -std=c++11 -I../../include -I.. -c *.cpp
if [ -f libcommon.a ]; then rm libcommon.a; fi
ar cru libcommon.a *.o
ranlib libcommon.a
cd ../compiler
echo "Making libcompiler..."
#cd preprocessor
#generate_parser.sh
#cd ../translator
#generate_parser.sh
#cd ..
$CXX $CXXFLAGS -DANGLE_TRANSLATOR_STATIC -DNDEBUG -DNOMINMAX -DANGLE_DISABLE_TRACE -DANGLE_DISABLE_PERF -DCOMPONENT_BUILD -DGL_APICALL= -DGL_GLEXT_PROTOTYPES= -DEGLAPI= -DANGLE_ENABLE_D3D9 -DUNICODE -D_UNICODE  -std=c++11 -I../../include -I.. -c preprocessor/*.cpp translator/*.cpp translator/timing/*.cpp translator/depgraph/*.cpp
$CXX $CXXFLAGS -O2 -DANGLE_TRANSLATOR_IMPLEMENTATION -DNDEBUG -DNOMINMAX -DANGLE_DISABLE_TRACE -DANGLE_DISABLE_PERF -DCOMPONENT_BUILD -DUNICODE -D_UNICODE -std=c++11 -I../../include -I.. -c translator/Shader*.cpp
if [ -f libcompiler.a ]; then rm libcompiler.a; fi
ar cru libcompiler.a *.o
ranlib libcompiler.a
echo "Making libGLESv2..."
cd ../libGLESv2
$CXX $CXXFLAGS -O2 -DANGLE_TRANSLATOR_STATIC -DGL_APICALL= -DGL_GLEXT_PROTOTYPES= -DEGLAPI= -DANGLE_ENABLE_D3D9 -DNDEBUG -DNOMINMAX -DANGLE_DISABLE_TRACE -DANGLE_DISABLE_PERF -DCOMPONENT_BUILD -DUNICODE -D_UNICODE  -std=c++11 -I../../include -I.. -I. -c *.cpp renderer/*.cpp renderer/d3d9/*.cpp ../third_party/murmurhash/MurmurHash3.cpp ../third_party/compiler/*.cpp
$CXX $CXXFLAGS -O2 -DANGLE_TRANSLATOR_STATIC -DGL_APICALL= -DGL_GLEXT_PROTOTYPES= -DEGLAPI= -DANGLE_ENABLE_D3D9 -DNDEBUG -DNOMINMAX -DANGLE_DISABLE_TRACE -DANGLE_DISABLE_PERF -DCOMPONENT_BUILD -DUNICODE -D_UNICODE  -std=c++11 -msse2 -I../../include -I.. -I. -c renderer/*sse2.cpp
windres $RCFLAGS -O coff -i libGLESv2.rc -o libGLESv2.res
#libGLESV2_mingw32.def
$CXX -shared $LDFLAGS libGLESV2.def -Wl,--out-implib,$IPATH/lib/libglesv2.dll.a -o $IPATH/bin/libglesv2.dll *.o *.res ../common/libcommon.a ../compiler/libcompiler.a -ld3d9 -ldxguid
echo "Making libEGL..."
cd ../libEGL
$CXX $CXXFLAGS -DANGLE_TRANSLATOR_STATIC -DGL_APICALL= -DGL_GLEXT_PROTOTYPES= -DEGLAPI= -DANGLE_ENABLE_D3D9 -DNDEBUG -DNOMINMAX -DANGLE_DISABLE_TRACE -DANGLE_DISABLE_PERF -DCOMPONENT_BUILD -DUNICODE -D_UNICODE  -std=c++11 -I../../include -I.. -I. -c *.cpp
windres $RCFLAGS -O coff -i libEGL.rc -o libEGL.res
$CXX -shared $LDFLAGS libegl.def  -Wl,--out-implib,$IPATH/lib/libegl.dll.a -o $IPATH/bin/libegl.dll *.o *.res ../compiler/libcompiler.a ../common/libcommon.a $IPATH/lib/libglesv2.dll.a -ld3d9 -ldxguid
cd ../..
cp -a include/* $IPATH/include/
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: glesv2
Description: ANGLE EGL GLESv2 layer for D3D
Version: 1.3
Requires: 
Libs: -lGLESv2 
Cflags: -I${includedir}'> $IPATH/lib/pkgconfig/glesv2.pc
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: egl
Description: ANGLE EGL GLESv2 layer for D3D
Version: 1.3
Requires: glesv2
Libs: -lEGL 
Cflags: -I${includedir}'> $IPATH/lib/pkgconfig/egl.pc
XXXX

cd $SPATH/libffi-3.2.1
configure --libdir=$IPATH/lib --disable-static --enable-portable-binary CFLAGS="$CFLAGS -O2"
make clean
make $PJOBS install
if [ "$MULTILIB" == 64 ]; then
set +e
mv $IPATH/lib64/*.* $IPATH/lib/
rm -rdf $IPATH/lib64/
set -e
fi
rm $IPATH/lib/*.la

cd $SPATH/win-iconv-0.0.6
make clean
make
cp iconv.h $IPATH/include/
cp libiconv.a $IPATH/lib/

:<<"XXXX"
# alternative
cd $SPATH/libiconv-1.14
configure -enable-static --enable-shared --enable-extra-encodings --disable-nls
make clean
cd libcharset/lib
cd ..
make install
cd ../lib
make libiconv.la
rm $IPATH/bin/libcharset*.dll
cp .libs/libiconv.a $IPATH/lib/
cp ../include/iconv.h $IPATH/include/
XXXX
cd $SPATH/gettext-0.18.3.2
if [ -f $IPATH/lib/libiconv.dll.a ]; then rm $IPATH/lib/libiconv.dll.a; fi
configure --without-emacs --with-included-libxml --with-included-libcroco --with-included-libunistring --with-included-glib --with-included-gettext --disable-static --disable-java --disable-csharp --disable-curses --disable-openmp --enable-threads=posix 
#CFLAGS="$CFLAGS -DLIBICONV_PLUG=1"
cd gettext-runtime/intl
make clean
make $PJOBS 
manifest
make install
cp $IPATH/lib/libintl.dll.a $IPATH/lib/libiconv.dll.a

cd $SPATH/libxml2-2.9.2
configure --without-python
make clean
make $PJOBS install
rm $IPATH/lib/*.la
#do not interfere msys
rm $IPATH/bin/xmlcatalog.exe $IPATH/bin/xmllint.exe

cd $SPATH/expat-2.1.0
configure
make clean
make $PJOBS install
set +e
rm $IPATH/lib/*.la $IPATH/bin/libxml2-2.dll $IPATH/bin/libexpat-1.dll
set -e
$CC xmlxpat.def -shared -o $IPATH/bin/libxmlxpat.dll $LDFLAGS -Wl,--whole-archive $IPATH/lib/libxml2.a $IPATH/lib/libexpat.a -Wl,--no-whole-archive -L$IPATH/lib -lz -lws2_32 -lintl -Wl,--out-implib,$IPATH/lib/libxml2.dll.a
cp $IPATH/lib/libxml2.dll.a $IPATH/lib/libexpat.dll.a

cd $SPATH/libpng-1.6.16
configure --disable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/jbigkit/libjbig
make clean
make $PJOBS
cp *.h $IPATH/include/
cp *.a $IPATH/lib/
cd $SPATH/jpeg/
if [ ! -d $IPATH/include/jpeg12 ]; then mkdir $IPATH/include/jpeg12; fi
cp *.h $IPATH/include/jpeg12/

# avoid jpeg 9 at the moment
cd $SPATH/mozjpeg-3.0
configure --disable-shared --enable-static --with-12bit --includedir=$IPATH/include/libjpeg12
make clean
make $PJOBS install
rm $IPATH/lib/*.la
mv $IPATH/lib/libjpeg.a $IPATH/lib/libjpeg12.a
cd $SPATH/jpeg-8d
configure --disable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la
cd $SPATH/mozjpeg-3.0
configure --disable-static --with-jpeg8 --without-turbojpeg
make clean
make $PJOBS
cp .libs/libjpeg-8.dll $IPATH/bin

cd $SPATH/tiff-4.0.3
configure --disable-static --disable-cxx --enable-jpeg12 --with-jpeg12-include-dir=`msyspath -m $IPATH/include/libjpeg12` --with-jpeg12-lib=-ljpeg12 CFLAGS="$CFLAGS -DTIF_PLATFORM_CONSOLE"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/jasper
configure --disable-static  --enable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libwebp-0.4.3
configure --disable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/dbus-1.10.2
configure --disable-static --disable-Werror
make clean
make $PJOBS install
cp -a $IPATH/share/doc/dbus $IPATH/share/gtk-doc/html/
rm $IPATH/lib/*.la

cd $SPATH/glib-2.46.2
configure --disable-static --with-threads=posix CFLAGS="$CFLAGS -O2"
make clean
if [ "$2" == "90" ]; then
make $PJOBS
manifest
fi
make $PJOBS install
rm $IPATH/lib/*.la
cp $IPATH/include/libintl.h $IPATH/include/glib-2.0/
#cp gio/gwin32*stream.h $IPATH/include/glib-2.0/gio/
#just in case
if [ "$CROSSX" == "1" ]; then
echo 'exec /opt/bin/${0##*/}.exe "$@"' > $IPATH/bin/glib-genmarshal
echo 'exec /opt/bin/${0##*/}.exe "$@"' > $IPATH/bin/glib-compile-schemas
echo 'exec /opt/bin/${0##*/}.exe "$@"' > $IPATH/bin/glib-compile-resources
fi

cd $SPATH/dbus-glib-0.104
if [ "$CROSSX" == "1" ]; then
if [ -f $IPATH/bin/glib-genmarshal.exe ]; then
mv $IPATH/bin/glib-genmarshal.exe $IPATH/bin/glib-genmarshal.bak
fi
configure --disable-static --disable-bash-completion --disable-abstract-sockets --disable-tests --with-dbus-binding-tool=/opt/bin/dbus-binding-tool
else
configure --disable-static --disable-bash-completion --disable-abstract-sockets
fi
make clean
make $PJOBS install
make check
#just in case
#echo 'exec /opt/bin/${0##*/}.exe "$@"' > $IPATH/bin/dbus-binding-tool
rm $IPATH/lib/*.la
if [ "$CROSSX" == "1" ]; then
    if [ -f $IPATH/bin/glib-genmarshal.exe ]; then
    mv $IPATH/bin/glib-genmarshal.bak $IPATH/bin/glib-genmarshal.exe
    fi
fi

cd $SPATH/ICU52
set +e
rm $IPATH/lib/libicu*.dll.a
rm $IPATH/bin/libicu*52.dll
set -e
configure --enable-shared --enable-static --disable-layout --disable-extras --disable-samples --with-data-packaging=archive --disable-tests --disable-dyload --with-library-bits=$CPUARCH
make clean 
make $PJOBS
make install
rm $IPATH/lib/libicu*52.dll
$CXX -shared $LDFLAGS -o $IPATH/bin/libicu52.dll -Wl,--whole-archive lib/libsicuio.a lib/libsicuuc.a lib/libsicuin.a stubdata/libsicudt.a -Wl,--no-whole-archive -Wl,--out-implib,$IPATH/lib/libicudt.dll.a
#some package innocently call these
cp $IPATH/lib/libicudt.dll.a $IPATH/lib/libicudata.dll.a
cp $IPATH/lib/libicudt.dll.a $IPATH/lib/libicuin.dll.a
cp $IPATH/lib/libicudt.dll.a $IPATH/lib/libicuuc.dll.a
cp $IPATH/lib/libicudt.dll.a $IPATH/lib/libicuio.dll.a
cp $IPATH/lib/libicuin.dll.a $IPATH/lib/libicui18n.dll.a
rm $IPATH/lib/libicu*.dll
rm $IPATH/lib/libsicu*.a
mv $IPATH/share/icu/52.1/icudt52l.dat $IPATH/bin/

cd $SPATH/libepoxy-1.3.1
configure --disable-static PYTHON=/c/python34/python
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/freetype-2.6.1
# looks stupid but the build system is rather unclen to do in-source build
if [ "$CROSSX" == "1" ]; then
if [ -f objs/apinames.exe ]; then rm -f objs/apinames.exe; fi
configure --disable-static --without-harfbuzz --prefix=$IPATH LIBPNG_CFLAGS="-I$IPATH/include/libpng16" LIBPNG_LDFLAGS="-lpng16" CC_BUILD=/mingw-w64/bin/gcc
make distclean
configure --disable-static --without-harfbuzz --prefix=$IPATH LIBPNG_CFLAGS="-I$IPATH/include/libpng16" LIBPNG_LDFLAGS="-lpng16" CC_BUILD=/mingw-w64/bin/gcc
else
configure --disable-static --without-harfbuzz --prefix=$IPATH LIBPNG_CFLAGS="-I$IPATH/include/libpng16" LIBPNG_LDFLAGS="-lpng16"
make distclean
configure --disable-static --without-harfbuzz --prefix=$IPATH LIBPNG_CFLAGS="-I$IPATH/include/libpng16" LIBPNG_LDFLAGS="-lpng16"
fi
make $PJOBS
make install
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include/freetype2
Name: FreeType 2
URL: http://freetype.org
Description: A free, high-quality, and portable font engine.
Version: 17.4.11
Requires:
Requires.private: zlib
Libs: -L${libdir} -lfreetype
Libs.private: -lbz2 -lpng16
Cflags: -I${includedir}'> $IPATH/lib/pkgconfig/freetype2.pc
rm $IPATH/lib/*.la

cd $SPATH/fontconfig-2.11.94
configure --disable-static --enable-iconv --disable-docs LIBS="-lregex -liconv"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/pixman-0.32.8
if [ -f $IPATH/lib/libpixman-1.dll.a ];then
rm $IPATH/lib/libpixman-1.dll.a
fi
if [ "$MULTILIB" == "64" ]; then
configure --disable-shared --disable-ssse3
else
configure --disable-shared --disable-sse2
fi
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/cairo-master
#configure --disable-interpreter --enable-wgl --enable-gl --enable-xml --disable-egl CPPFLAGS="$CPPFLAGS -DGLEW_STATIC"
#-enable-glesv2 --enable-egl
configure --disable-interpreter --enable-pthread CFLAGS="$CFLAGS -O2" CPPFLAGS="$CPPFLAGS -DGLEW_STATIC"
#configure --disable-interpreter --enable-pthread
make clean
make $PJOBS install
rm $IPATH/lib/*.la $IPATH/bin/libcairo-2.dll
#name mangling
echo "LIBRARY \"libcairo-gobject-2.dll\"
EXPORTS
"> cairo_pixman_gobject.def
nm -g -n -C --defined-only $IPATH/lib/libcairo-gobject.a $IPATH/lib/libcairo.a $IPATH/lib/libpixman-1.a | grep " [DT] " | cut -d" " -f3 | grep "^[^_]" >> cairo_pixman_gobject.def
$CC -shared cairo_pixman_gobject.def -Wl,--whole-archive $IPATH/lib/libcairo-gobject.a $IPATH/lib/libcairo.a -Wl,--no-whole-archive -o $IPATH/bin/libcairo-gobject-2.dll $LDFLAGS $IPATH/lib/libpixman-1.a -lgdi32 -lepoxy -lpng -lz -lfontconfig -lfreetype -ldl -lgobject-2.0 -lglib-2.0 -lwinspool -lmsimg32 -Wl,--out-implib,$IPATH/lib/libcairo-gobject.dll.a
# -legl -lglesv2
cp $IPATH/lib/libcairo-gobject.dll.a $IPATH/lib/libcairo.dll.a 
cp $IPATH/lib/libcairo-gobject.dll.a $IPATH/lib/libpixman-1.dll.a

if [ "$2" == "90" ]; then
list="27 31 32"
else
list="27 33 34"
fi
for i in $list; do
    if [ "$MULTILIB" == "64" ] && [ "$CPUARCH" == "$MULTILIB" ]; then
        if [ -f ${SYS64DIR}\\system32\\python$i.dll ]; then
            gendef - ${SYS64DIR}\\system32\\python$i.dll > $IPATH/lib/python$i.def
        elif [ -f ${SYSTEMDRIVE}\\python$i-64\\python$i.dll ]; then
            gendef - ${SYSTEMDRIVE}\\python$i-64\\python$i.dll > $IPATH/lib/python$i.def
        elif [ -f D:\\python$i-64\\python$i.dll ]; then
            gendef - D:\\python$i-64\\python$i.dll > $IPATH/lib/python$i.def
        else 
            echo "cannot find one of python dll"
            exit
        fi
        dlltool  --as-flags=--64 -m i386:x86-64 -d $IPATH/lib/python$i.def -D python$i.dll -l $IPATH/lib/libpython$i.dll.a
    elif [ "$MULTILIB" != "64" ] && [ "$CPUARCH" == "64" ]; then
        if [ -f ${SYSTEMROOT}\\syswow64\\python$i.dll ]; then
            gendef - ${SYSTEMROOT}\\syswow64\\python$i.dll > $IPATH/lib/python$i.def
        elif [ -f ${SYSTEMDRIVE}\\python$i\\python$i.dll ]; then
            gendef - ${SYSTEMDRIVE}\\python$i\\python$i.dll > $IPATH/lib/python$i.def
        else 
            echo "cannot find one of python dll"
            exit
        fi
        dlltool -d $IPATH/lib/python$i.def -D python$i.dll -l $IPATH/lib/libpython$i.dll.a
    else
        if [ "$CROSSX" == "1" ]; then
            if [ -f ${SYSTEMDRIVE}\\python$i-64\\python$i.dll ]; then
                gendef - ${SYSTEMDRIVE}\\python$i-64\\python$i.dll > $IPATH/lib/python$i.def
            else 
                echo "cannot find python $i dll"
                exit
            fi
            dlltool  --as-flags=--64 -m i386:x86-64 -d $IPATH/lib/python$i.def -D python$i.dll -l $IPATH/lib/libpython$i.dll.a
        else 
            if [ -f ${SYSTEMROOT}\\system32\\python$i.dll ]; then
                gendef - ${SYSTEMROOT}\\system32\\python$i.dll > $IPATH/lib/python$i.def
            elif [ -f ${SYSTEMDRIVE}\\python$i\\python$i.dll ]; then
                gendef - ${SYSTEMDRIVE}\\python$i\\python$i.dll > $IPATH/lib/python$i.def
            else 
                echo "cannot find one of python dll"
                exit
            fi
            dlltool -d $IPATH/lib/python$i.def -D python$i.dll -l $IPATH/lib/libpython$i.dll.a
        fi
    fi
    if [ ! -d $IPATH/py$i/lib/site-packages ]; then
        mkdir -p $IPATH/py$i/lib/site-packages
    fi
done
if [ "$2" == "90" ]; then
    cp $IPATH/lib/libpython32.dll.a $IPATH/lib/libpython3.2.dll.a
    cp $IPATH/lib/libpython31.dll.a $IPATH/lib/libpython3.1.dll.a
else
    cp $IPATH/lib/libpython34.dll.a $IPATH/lib/libpython3.4.dll.a
    cp $IPATH/lib/libpython33.dll.a $IPATH/lib/libpython3.3.dll.a
fi
# especially need for detection
cp $IPATH/lib/libpython27.dll.a $IPATH/lib/libpython2.7.dll.a
:<<"XXXX"
cd $SPATH/dbus-python-1.2.0
if [ "$2" == "90" ]; then
list="27 31 32"
else
list="33 34"
fi
for i in $list; do
if [ "$CROSSX" == "1" ]; then
configure PYTHON=python$i --disable-html-docs --disable-api-docs --prefix=$IPATH/py$i
else
configure PYTHON=python$i$MULTILIB --disable-html-docs --disable-api-docs --prefix=$IPATH/py$i
fi
make clean
make $PJOBS install
done
XXXX

if [ "$CROSSX" != "1" ]; then
cd $SPATH/gobject-introspection-1.46.0
# girs missing shared-library
configure --with-cairo --disable-static PYTHON=python27$MULTILIB
make clean
make install V=1
cd docs/reference
make install
rm $IPATH/lib/*.la
else
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
bindir=${exec_prefix}/bin
datarootdir=${prefix}/share
datadir=${datarootdir}
includedir=${prefix}/include
g_ir_scanner=${bindir}/g-ir-scanner
g_ir_compiler=${bindir}/g-ir-compiler.exe
g_ir_generate=${bindir}/g-ir-generate.exe
gidatadir=${datadir}/gobject-introspection-1.0
girdir=${datadir}/gir-1.0
typelibdir=${libdir}/girepository-1.0
Cflags: -I${includedir}/gobject-introspection-1.0 
Requires: glib-2.0 gobject-2.0
Requires.private: gmodule-2.0 libffi
Libs: -L${libdir}
Libs.private: 
Name: gobject-introspection
Description: GObject Introspection
Version: 1.46.0' > $IPATH/lib/pkgconfig/gobject-introspection-1.0.pc
fi

if [ "$CROSSX" != "1" ]; then
if [ ! -d $IPATH/include/pycairo ]; then
mkdir $IPATH/include/pycairo
fi
if [ "$2" == "90" ]; then
cd $SPATH/py2cairo-1.10.0/src
if [ ! -d $IPATH/py27/lib/site-packages/cairo ]; then
mkdir -p $IPATH/py27/lib/site-packages/cairo
fi
$CC -shared $CFLAGS -O2 -I. `python27$MULTILIB-config --cflags` `pkg-config --cflags cairo` -o $IPATH/py27/lib/site-packages/cairo/_cairo.pyd *.c $LDFLAGS `python27$MULTILIB-config --ldflags` `pkg-config --libs cairo`
cp __init__.py $IPATH/py27/lib/site-packages/cairo/
cp pycairo.h $IPATH/include/pycairo/
cp pycairo.pc $IPATH/lib/pkgconfig/
fi
fi

if [ "$CROSSX" != "1" ]; then
cd $SPATH/pycairo-1.10.0/src
if [ "$2" == "90" ]; then
list="31 32"
else
list="33 34"
fi
for i in $list; do
    if [ ! -d $IPATH/py$i/lib/site-packages/cairo ]; then
        mkdir -p $IPATH/py$i/lib/site-packages/cairo
    fi
    $CC -shared $CFLAGS -O2 -I. `python$i$MULTILIB-config --cflags` `pkg-config --cflags cairo` -o $IPATH/py$i/lib/site-packages/cairo/_cairo.pyd *.c $LDFLAGS `python$i$MULTILIB-config --ldflags` `pkg-config --libs cairo`
    cp __init__.py $IPATH/py$i/lib/site-packages/cairo/
done
cp py3cairo.h $IPATH/include/pycairo/
cp py3cairo.pc $IPATH/lib/pkgconfig/
fi

if [ "$CROSSX" != "1" ]; then
cd $SPATH/pygobject-3.18.2
if [ "$2" == "90" ]; then
list="27 31 32"
else
list="33 34"
fi
for i in $list; do
configure --enable-cairo --enable-compile-warnings=minimum --with-python=python$i$MULTILIB --prefix=$IPATH/py$i LIBS=-lffi CFLAGS="$CFLAGS -O2"
make clean
make $PJOBS V=1 install
done
fi

cd $SPATH/graphite2-1.2.4
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_CXX_FLAGS="$CPPFLAGS -DGRAPHITE2_STATIC"
make clean
make $PJOBS
make install
cp src/CMakeFiles/graphite2.dir/objects.a $IPATH/lib/libgraphite2.a
rm $IPATH/lib/libgraphite2.dll.a $IPATH/bin/libgraphite2.dll

cd $SPATH/harfbuzz-1.0.3
mv $IPATH/lib/libstdc++.dll.a $IPATH/lib/libstdc++_s.a
configure --with-uniscribe --with-graphite2 --with-gobject $INTROSPECT CPPFLAGS="$CPPFLAGS -DGRAPHITE2_STATIC" --with-icu
make clean
make $PJOBS install 
rm $IPATH/lib/*.la
mv  $IPATH/lib/libstdc++_s.a $IPATH/lib/libstdc++.dll.a

cd $SPATH/atk-2.18.0
configure --disable-static $INTROSPECT
make clean
make $PJOBS 
manifest
make install
rm $IPATH/lib/*.la

cd $SPATH/libdatrie-0.2.8
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libthai-0.1.20
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/pango-1.38.0
configure --disable-static $INTROSPECT
make clean
make $PJOBS
manifest
make install
rm $IPATH/lib/*.la

cd $SPATH/gdk-pixbuf-2.32.0
configure --disable-static --with-included-loaders=png --disable-modules $INTROSPECT
make clean
make $PJOBS
manifest
make install
rm $IPATH/lib/*.la

cd $SPATH/libcroco-0.6.9
configure --disable-shared --enable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/librsvg-2.40.11
configure --disable-static --disable-pixbuf-loader $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#if [ ! -d $IPATH/include/boost ]; then
#cd $IPATH/include
#tar -xf $SPATH/boost_1_55_0/boost.tar.xz
#fi

cd $SPATH/gdk-pixbuf-2.32.0
configure $INTROSPECT --disable-static --with-included-loaders --with-gdiplus --with-libjasper --with-libtiff --with-libjpeg --disable-modules CPPFLAGS="$CPPFLAGS -I$IPATH/include/librsvg-2.0/librsvg -I$IPATH/include/cairo" LIBS="-lrsvg-2 -lwebp -ljpeg -lgdiplus"
make clean
make $PJOBS
manifest
make install
rm $IPATH/lib/*.la

cd $SPATH/orc-0.4.24
configure --disable-static --enable-backend=sse,mmx CFLAGS="$CFLAGS -O2"
make clean
make $PJOBS install
rm $IPATH/lib/*.la
#just in case
if [ "$CROSSX" == "1" ]; then
echo 'exec /opt/bin/${0##*/}.exe "$@"' > $IPATH/bin/orcc
fi

cd $SPATH/SDL-1.2.15
configure --disable-static --disable-stdio-redirect CFLAGS="$CFLAGS -O2"
make clean
make $PJOBS install
rm $IPATH/lib/*.la $IPATH/bin/sdl-config

cd $SPATH/gstreamer-1.6.1
configure --disable-static $INTROSPECT CFLAGS="$CFLAGS -O2"
make clean
make $PJOBS install
cd libs/gst/check
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/json-glib-1.0.4
configure --disable-static  $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/cogl-1.22.0
# --with-gles2-libname=libglesv2.dll --enable-null-egl-platform --enable-cogl-gles2 --enable-gles2
configure --enable-sdl $INTROSPECT CFLAGS="$CFLAGS -O2"
make clean
set +e
make $PJOBS
set -e
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gettext-0.18.3.2
if [ -f $IPATH/lib/libiconv.dll.a ]; then rm $IPATH/lib/libiconv.dll.a; fi
configure --without-emacs --with-included-libunistring --with-included-gettext --disable-java --disable-csharp --disable-curses --disable-openmp --enable-threads=posix 
#CFLAGS="$CFLAGS -DLIBICONV_PLUG=1"
make clean
make $PJOBS 
manifest
make install
rm $IPATH/lib/*.la 
rm $IPATH/lib/libgettextpo.dll.a
cp $IPATH/lib/libintl.dll.a $IPATH/lib/libiconv.dll.a

cd $SPATH/gtk+-3.18.5
set +e
rm gtk/extract-strings.exe
rm gtk/extract-strings
set -e
if [ "$CROSSX" == "1" ]; then
configure --enable-win32-backend --with-included-immodules --enable-broadway-backend --enable-gtk2-dependency PKG_CONFIG_FOR_BUILD=pkg-config $INTROSPECT
echo 'exec /opt/bin/${0##*/}.exe "$@"' > gtk/extract-strings
else
configure --enable-win32-backend --with-included-immodules --enable-broadway-backend $INTROSPECT  CC_FOR_BUILD="$CC" CFLAGS="$CFLAGS -O2" CC="gcc $RTVER"
fi
make clean
if [ "$2" == "90" ]; then
make $PJOBS
manifest
fi
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/unico-1.0.3+14.04.20140109
configure --disable-static
make clean
make $PJOBS install

cd $SPATH/clutter-1.24.2
# --enable-egl-backend
configure --disable-static --enable-gdk-backend $INTROSPECT
make clean
if [ -f clutter/win32/resources.o ];then
rm clutter/win32/resources.o
fi
make $PJOBS
manifest
make install
rm $IPATH/lib/*.la

cd $SPATH/libgpg-error-1.20
echo '#!/bin/sh
exec /opt/bin/win_iconv.exe "$@"' > $IPATH/bin/iconv
if [ -f $IPATH/lib/libgpg-error.dll.a ]; then rm $IPATH/lib/libgpg-error.dll.a; fi
if [ "$CROSSX" == "1" ]; then
configure --disable-shared --enable-static --disable-nls CC_FOR_BUILD=/mingw-w64/bin/gcc.exe
else
configure --disable-shared --enable-static --disable-nls
fi
make clean
make $PJOBS install
rm $IPATH/lib/*.la
rm $IPATH/bin/iconv

cd $SPATH/libgcrypt-1.5.4
if [ -f $IPATH/lib/libgcrypt.dll.a ]; then rm $IPATH/lib/libgcrypt.dll.a; fi
if [ -f $IPATH/lib/libgpg-error.dll.a ]; then rm $IPATH/lib/libgpg-error.dll.a; fi
if [ "$MULTILIB" == "64" ]; then
    if [ "$CROSSX" == "1" ]; then
    configure --disable-static --enable-shared --disable-asm --disable-padlock-support CC_FOR_BUILD=/mingw-w64/bin/gcc.exe
    else
    configure --disable-static --enable-shared --disable-asm --disable-padlock-support
    fi
else 
configure --disable-static --enable-shared
fi
make clean
make $PJOBS install
rm $IPATH/lib/*.la
cp $IPATH/lib/libgcrypt.dll.a $IPATH/lib/libgpg-error.dll.a

cd $SPATH/libtasn1-4.7
if [ -f $IPATH/lib/libtasn1.dll.a ]; then
rm $IPATH/lib/libtasn1.dll.a
fi
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/p11-kit-0.23.1
configure --disable-static --without-trust-paths --disable-nls LIBS=-lffi
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libidn-1.29
configure --disable-static --disable-nls --disable-csharp --disable-java 
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gmp-5.1.3
set +e
make distclean
set -e
if [ "$MULTILIB" == "64" ]; then
configure --disable-shared --enable-static ABI=64 --host=x86_64-w64-mingw32
#--host=x86_64-w64-mingw32
#--enable-fat
#--host=pentium3-w64-mingw32
else
configure --disable-shared --enable-static ABI=32 --host=pentium3-w64-mingw32
fi
make $PJOBS install
rm $IPATH/lib/*.la
#rm $IPATH/lib/libgmp-10.dll
#rm $IPATH/lib/libgmp.lib

cd $SPATH/nettle-2.7.1
#cd $SPATH/nettle-3.1.1
if [ -f $IPATH/lib/libgmp.dll.a ]; then rm $IPATH/lib/libgmp.dll.a; fi
set +e
make distclean
set -e
configure --disable-shared --disable-openssl
make $PJOBS
make install
#rm $IPATH/lib/libnettle.dll.a $IPATH/lib/libhogweed.dll.a

#cd $SPATH/gnutls-2.12.23
#cd $SPATH/gnutls-3.4.4.1
cd $SPATH/gnutls-3.2.21
if [ -f $IPATH/lib/libnettle.dll.a ]; then rm $IPATH/lib/libnettle.dll.a; fi
if [ -f $IPATH/lib/libtasn1.dll.a ]; then rm $IPATH/lib/libtasn1.dll.a; fi
if [ -f $IPATH/lib/libgmp.dll.a ]; then rm $IPATH/lib/libgmp.dll.a; fi
if [ -f $IPATH/lib/libhogweed.dll.a ]; then rm $IPATH/lib/libhogweed.dll.a; fi
configure --disable-static --disable-nls --disable-doc --with-included-libtasn1 --disable-guile --disable-openssl-compatibility --disable-cxx
#configure --disable-static --with-libgcrypt --disable-nls --disable-doc --with-included-libtasn1 --disable-guile --disable-openssl-compatibility --disable-cxx
make clean
make $PJOBS
make $PJOBS install
rm $IPATH/lib/*.la
cp $IPATH/lib/libgnutls.dll.a $IPATH/lib/libtasn1.dll.a
cp $IPATH/lib/libgnutls.dll.a $IPATH/lib/libnettle.dll.a
cp $IPATH/lib/libgnutls.dll.a $IPATH/lib/libhogweed.dll.a
cp $IPATH/lib/libgnutls.dll.a $IPATH/lib/libgmp.dll.a

cd $SPATH/p11-kit-0.23.1
configure --disable-static --without-trust-paths --disable-nls LIBS=-lffi
make clean
make install
rm $IPATH/lib/*.la

cd $SPATH/sqlite-autoconf-3080600
configure --disable-static --disable-readline --enable-shared CPPFLAGS="$CPPFLAGS -DSQLITE_ENABLE_COLUMN_METADATA"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libproxy-0.4.11/
# gir need recompile
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH  -DCMAKE_BUILD_TYPE=MinSizeRel
make clean
make $PJOBS install
cp libproxy-1.0.pc $IPATH/lib/pkgconfig/
if [ "$CROSSX" != "1" ]; then
cp libproxy/Libproxy-1.0.gir $IPATH/share/gir-1.0/
cp libproxy/Libproxy-1.0.typelib $IPATH/lib/girepository-1.0/
fi
cp libproxy/CMakeFiles/libproxy.dir/objects.a $IPATH/lib/libproxy.a
cp libmodman/libmodman.a $IPATH/lib/libmodman.a
mv $IPATH/liblibproxy.dll.a $IPATH/lib/libproxy.dll.a
mv $IPATH/libproxy.dll $IPATH/bin/libproxy.dll
mv $IPATH/proxy.exe $IPATH/bin/proxy.exe

cd $SPATH/gsettings-desktop-schemas-3.18.1
configure $INTROSPECT
make clean
make install

cd  $SPATH/glib-networking-2.46.1
configure --with-ca-certificates=curl-ca-bundle.crt --disable-static
make clean
make $PJOBS
if [ "$CROSSX" == "1" ]; then
set +e
make install -k
set -e
echo "libgiognomeproxy.dll: gio-proxy-resolver
libgiognutls.dll: gio-tls-backend
libgiolibproxy.dll: gio-proxy-resolver" > $IPATH/lib/gio/modules/giomodule.cache
else
make install
fi

cd $SPATH/libsoup-2.52.2
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/rest-0.7.93
configure --without-gnome --with-ca-certificates=curl-ca-bundle.crt  $INTROSPECT
set +e
make clean -k
set -e
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gnome-themes-standard-3.18.0
configure --disable-gtk2-engine
make $PJOBS

cd $SPATH/hicolor-icon-theme-0.12
configure
make install
if [ ! -d $IPATH/share/icons/gnome ]; then
mkdir -p $IPATH/share/icons/gnome
cp $IPATH/share/icons/hicolor/index.theme $IPATH/share/icons/gnome/
fi

cd $SPATH/iso-codes-3.23
configure
make clean
make install
:<<"XXXX"
cd $SPATH/adwaita-icon-theme-3.18.0
configure
make install
XXXX
cd $SPATH/libeasyfc-0.13.0
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/icon-naming-utils-0.8.90
configure
make install

#cd $SPATH/gnome-icon-theme-symbolic-3.12.0
#configure
#make clean
#make install

cd $SPATH/libexif
configure --disable-shared --disable-nls
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libnotify-0.7.6
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/glade-3.18.3
configure --enable-gladeui $INTROSPECT 
make clean
make $PJOBS
manifest
make install
rm $IPATH/lib/*.la
if [ "$2" == "90" ]; then
list="27 31 32"
else
list="33 34"
fi
for i in $list; do
cd $SPATH/glade-3.18.3
configure --enable-gladeui PYTHON=/bin/python$i$MULTILIB PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$IPATH/py$i/lib/pkgconfig" PYTHON_INCLUDES=`python$i$MULTILIB-config --cflags` PYTHON_LIBS=-lpython$i
cd plugins/python
make clean
make $PJOBS
cp .libs/libgladepython.dll $IPATH/lib/glade/modules/libgladepython$i.dll
done

cd $SPATH/gtksourceview-3.18.1
configure --disable-static --enable-glade-catalog $INTROSPECT 
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libogg-1.3.2
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libvorbis-1.3.5
configure --disable-shared --disable-docs --disable-examples
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libtheora
configure --disable-shared --disable-spec --disable-examples CFLAGS="$CFLAGS -O2"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/celt-0.5.1.3
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/opus-1.1
configure --disable-shared --enable-float-approx --enable-custom-modes
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#cd $SPATH/opus-tools-0.1.9
#configure
#make clean
#make $PJOBS 

cd $SPATH/flac-1.3.1
configure --disable-shared --enable-sse
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libvisual-0.4.0
configure --disable-nls CFLAGS="$CFLAGS -O2"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libvorbisidec-1.2.0-dave
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gst-plugins-base-1.6.1
configure --disable-static --enable-experimental $INTROSPECT LIBS=-logg
make clean
make $PJOBS install
cd docs/plugins
make install
rm $IPATH/lib/*.la

# fixme crashed in 64bit
cd $SPATH/gst-python-1.6.1
if [ "$2" == "90" ]; then
list="27 31 32"
else
list="33 34"
fi
for i in $list; do
PYINC=`python$i$MULTILIB-config --cflags`
echo $PYINC
set +e
make distclean -k
find . -name *.Plo -exec rm {} +
set -e
configure --disable-static PYTHON=python$i CPPFLAGS="$CPPFLAGS $PYINC" LIBS=-lpython$i PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$IPATH/py$i/lib/pkgconfig" --prefix=$IPATH/py$i --with-pygi-overrides-dir=$IPATH/py$i/lib/site-packages/gi/overrides PYTHON_INCLUDES=$PYINC CFLAGS="$CFLAGS -O2"
make clean
make install 
mv $IPATH/py$i/lib/bin/libgstpythonplugin.dll $IPATH/py$i/lib/gstreamer-1.0/libgstpythonplugin-py$i.dll
done

cd $SPATH/clutter-box2d-master
mv $IPATH/lib/libstdc++.dll.a $IPATH/lib/libstdc++_s.a
configure --disable-static $INTROSPECT CXXFLAGS="$CXXFLAGS -O2"
make clean
make $PJOBS 
make install
rm $IPATH/lib/*.la
mv $IPATH/lib/libstdc++_s.a $IPATH/lib/libstdc++.dll.a

cd $SPATH/clutter-gtk-1.6.2
configure --disable-static --enable-debug=minimum $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/PDCurses-3.4/win32
make -f mingwin32.mak WIDE=Y clean
make -f mingwin32.mak WIDE=Y
cp ../curses.h $IPATH/include/
cp pdcurses.a $IPATH/lib/libcurses.a

# what a troublesome configure
export CC__=$CC
export CXX__=$CXX
export CC=gcc
export CXX=g++
cd $SPATH/openssl-1.0.2d
./configure mingw$MULTILIB enable-static-engine zlib threads --prefix=$IPATH $CFLAGS $LDFLAGS
make clean
make
make install
export CC=$CC__
export CXX=$CXX__
unset CC__
unset CXX__
rm -f $IPATH/lib/libcrypto.dll.a $IPATH/lib/libssl.dll.a $IPATH/bin/libeay32.dll $IPATH/bin/ssleay32.dll
$CC -shared -o $IPATH/bin/libopenssl.dll -Wl,--out-implib,$IPATH/lib/libssl.dll.a -Wl,--whole-archive libssl.a libcrypto.a -Wl,--no-whole-archive $LDFLAGS -lz -lws2_32 -lgdi32 -lcrypt32 -lsecur32
cp $IPATH/lib/libssl.dll.a $IPATH/lib/libcrypto.dll.a

cd $SPATH/libssh2-1.6.0
configure --disable-shared --enable-static --with-libgcrypt -without-openssl --without-wincng --with-libz CPPFLAGS="$CPPFLAGS -DLIBSSH2_LIBRARY=1"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgit2-0.23.2
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH  -DCMAKE_BUILD_TYPE=MinSizeRel -DUSE_ICONV=ON -DUSE_SSH=ON -DBUILD_SHARED_LIBS=OFF -DTHREADSAFE=ON -DBUILD_CLAR=OFF
#-DOPENSSL_ROOT_DIR=$IPATH -DOPENSSL_LIBRARIES=$IPATH/lib -DOPENSSL_INCLUDE_DIR=$IPATH/include -DSSL_EAY=$IPATH/lib/libssl.dll.a  -DLIB_EAY=$IPATH/lib/libcrypto.dll.a
make clean
make $PJOBS install
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: libgit2
Description: The git library, take 2
Version: 0.23.2
Requires: libssh2,zlib
Cflags: -I${includedir}
Libs: -L${libdir} -lgit2 -lrpcrt4 -lole32 -lwinhttp -lcrypt32
' > $IPATH/lib/pkgconfig/libgit2.pc

cd $SPATH/lcms2-2.7
configure --disable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/openjpeg-2.1.0
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DBUILD_SHARED_LIBS=ON -DCMAKE_C_FLAGS="$CFLAGS -D_OPENSLIDE_BUILDING_DLL"
make clean
make $PJOBS install
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include/openjpeg-2.1
Name: openjp2
Description: JPEG2000 library (Part 1 and 2)
URL: http://www.openjpeg.org/
Version: 2.1.0
Libs: -L${libdir} -lopenjp2
Libs.private: -lm
Cflags: -I${includedir}
' > $IPATH/lib/pkgconfig/libopenjp2.pc

if [ "$CROSSX" != "1" ]; then
cd $SPATH/ilmbase-2.2.0
# need explicitly sse2 opt otherwise it break
configure CXXFLAGS="$CXXFLAGS -msse2"
make clean
make $PJOBS install
rm $IPATH/lib/*.la
cd $SPATH/openexr-2.2.0
configure CXXFLAGS="$CXXFLAGS -msse2"
make clean
make $PJOBS install
rm $IPATH/lib/*.la
$CXX $LDFLAGS -shared -o $IPATH/bin/libopenexr-2.dll -Wl,-whole-archive $IPATH/lib/libIlmImf.a $IPATH/lib/libIlmImfUtil.a $IPATH/lib/libIlmThread.a $IPATH/lib/libImath.a $IPATH/lib/libIexMath.a $IPATH/lib/libIex.a $IPATH/lib/libHalf.a -Wl,--no-whole-archive -Wl,--out-implib,$IPATH/lib/libIlmImf.dll.a -lz
cp $IPATH/lib/libIlmImf.dll.a $IPATH/lib/libIlmThread.dll.a
cp $IPATH/lib/libIlmImf.dll.a $IPATH/lib/libIlmImfUtil.dll.a
cp $IPATH/lib/libIlmImf.dll.a $IPATH/lib/libImath.dll.a
cp $IPATH/lib/libIlmImf.dll.a $IPATH/lib/libIexMath.dll.a
cp $IPATH/lib/libIlmImf.dll.a $IPATH/lib/libIex.dll.a
cp $IPATH/lib/libIlmImf.dll.a $IPATH/lib/libHalf.dll.a
cd $IPATH/bin/
rm libIlmImf*.dll libIlmThread*.dll libImath*.dll libIex*.dll libHalf*.dll
fi

:<<"XXXX"
# use luajit below
cd $SPATH/lua-5.1.5
make PREFIX=$IPATH mingw clean
make PREFIX=$IPATH $PJOBS mingw
make PREFIX=$IPATH $PJOBS mingw install
echo '
prefix=
exec_prefix=${prefix}
libdir=${prefix}/lib
includedir=${prefix}/include
Name: Lua
Description: An Extensible Extension Language
Version: 5.1.5
Requires: 
Libs: -L${libdir} -llua -lm
Cflags: -I${includedir}
' > $IPATH/lib/pkgconfig/lua5.1.pc
XXXX

cd $SPATH/luajit-2.0.3/src
make clean
make HOST_CC="$CC" CFLAGS="$CFLAGS -O3" TARGET_SYS=Windows PREFIX=$IPATH $PJOBS
cd ..
make PREFIX=$IPATH install
cp src/liblua51.dll $IPATH/bin/
cp src/luajitw.exe $IPATH/bin/
cp $IPATH/include/luajit-2.0/* $IPATH/include/
cp src/liblua.dll.a $IPATH/lib/
cp src/liblua.dll.a $IPATH/lib/libluajit-2.0.dll.a
cp $IPATH/lib/pkgconfig/luajit.pc $IPATH/lib/pkgconfig/lua.pc
#cp -a $IPATH/share/luajit-2.0.3/jit $IPATH/share/lua/5.1/
echo '
prefix=
exec_prefix=${prefix}
includedir=${prefix}/include
libdir=${prefix}/lib
Name: Lua
Description: Just-in-time compiler for Lua
URL: http://luajit.org
Version: 5.1.5
Requires:
Libs: -L${libdir} -llua
Libs.private: -Wl,-E -lm -ldl
Cflags: -I${includedir}
'>$IPATH/lib/pkgconfig/lua5.1.pc

cd $SPATH/lgi-0.9.0
make clean
make CFLAGS="$CFLAGS $CPPFLAGS -O2"
make install PREFIX=$IPATH

cd $SPATH/libspiro
configure --enable-static --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/exiv2
set +e
make distclean
set -e
configure --disable-shared --enable-static CPPFLAGS="$CPPFLAGS $(pkg-config --cflags glib-2.0)" LIBS="$(pkg-config --libs glib-2.0)"
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/lensfun-0.2.5/libs/lensfun
set +e
rm *.o *.a
set -e
if [ "$MULTILIB" == "64" ]; then
$CXX $CFLAGS $CPPFLAGS -msse2 $(pkg-config --cflags glib-2.0) -DVECTORIZATION_SSE2=1 -fvisibility=hidden -Wno-non-virtual-dtor -I../../include -c *.cpp
else
set +e
$CXX $CFLAGS $CPPFLAGS $(pkg-config --cflags glib-2.0) -DVECTORIZATION_SSE=1 -fvisibility=hidden -Wno-non-virtual-dtor -I../../include -c *.cpp
set -e
fi
ar cru $IPATH/lib/liblensfun.a *.o
ranlib $IPATH/lib/liblensfun.a
cp $SPATH/lensfun-0.2.5/include/lensfun/lensfun.h $IPATH/include/
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: lensfun
Description: A photographic lens database and access library
Version: 0.2.5
Requires: glib-2.0,libpng
Cflags: -I${includedir}
Libs: -L${libdir} -llensfun -lregex
' > $IPATH/lib/pkgconfig/lensfun.pc

cd $SPATH/babl-0.1.12
if [ "$MULTILIB" == "64" ]; then
configure --disable-static CFLAGS="$CFLAGS -O2"
else
configure --disable-sse2 --disable-static CFLAGS="$CFLAGS -O2"
fi
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/hspell-1.2
configure --enable-fatverb
make clean
make libhspell.a
cp hspell.h $IPATH/include/
cp libhspell.a $IPATH/lib/

#begin c++
cd $SPATH/aspell
configure --disable-static --enable-win32-relocatable --enable-compile-in-filters --disable-nls
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/hunspell-1.3.2
configure --enable-threads=win32 --with-experimental --disable-shared --disable-nls 
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libvoikko-3.5
configure  --disable-shared
cp config.h.w64 config.h
touch config.h
make clean
make $PJOBS install
rm $IPATH/lib/*.la
#end c++

cd $SPATH/enchant
configure --disable-static  LIBS="-laspell -lstdc++"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gssdp-0.14.12
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gupnp-0.20.14
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gdl-3.18.0
configure --disable-static $INTROSPECT 
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/osm-gps-map-1.0.2
configure --disable-static --disable-gtk-doc $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/memphis-master
# included libtool are crewed up in crosscompile
# thus linking patch applied at makefile.am
# if from vanila this need libtoolize and autoreconf -if
# and repatching
configure --disable-static $INTROSPECT 
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libchamplain-0.12.11
configure --enable-memphis --disable-static --disable-debug $INTROSPECT 
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgee-0.16.1
# gir missing shared-library
configure --disable-static $INTROSPECT 
find . -name *.lo -exec rm {} +
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/lasem-0.4.3
configure --disable-static $INTROSPECT 
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgsf-1.14.34
configure --disable-static --enable-compile-warnings=minimum $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libxslt-1.1.28
configure --disable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la
#do not interfere msys
rm $IPATH/bin/xsltproc.exe

cd $SPATH/ghostscript-9.14
#configure --with-drivers=FILES --with-system-libtiff --with-libidn --with-jbig2dec --enable-threadsafe --enable-cairo --enable-fontconfig --enable-freetype --without-x --disable-contrib --disable-openjpeg --with-gs=gswin${CPUARCH}c 
configure --with-drivers=display,plan,planc,plang,plank,planm,epswrite,ps2write,eps2write,pdfwrite --disable-cups --enable-cairo --with-system-libtiff --with-jbig2dec --disable-openjpeg --enable-fontconfig --enable-freetype --disable-contrib --without-x LIBS=-lopenjp2
make soclean
make $PJOBS so
make soinstall
if [ "$MULTILIB" == "64" ]; then
mv $IPATH/bin/gsc.exe $IPATH/bin/gswin64c.exe
else
mv $IPATH/bin/gsc.exe $IPATH/bin/gswin32c.exe
fi

cd $SPATH/libspectre-0.2.7
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/goffice-0.10.24
configure --with-config-backend=gsettings --enable-compile-warnings=no $INTROSPECT
make clean
make $PJOBS install
cd docs
make install
rm $IPATH/lib/*.la

cd $SPATH/geoclue-0.12.99
#echo 'exec $IPATH90/bin/${0##*/}.exe "$@"' > $IPATH/bin/dbus-binding-tool
if [ "$CROSSX" == "1" ]; then
if [ -f $IPATH/bin/glib-genmarshal.exe ]; then
mv $IPATH/bin/glib-genmarshal.exe $IPATH/bin/glib-genmarshal.bak
fi
fi
configure --disable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la
if [ "$CROSSX" == "1" ]; then
if [ -f $IPATH/bin/glib-genmarshal.bak ]; then
mv $IPATH/bin/glib-genmarshal.bak $IPATH/bin/glib-genmarshal.exe
fi
fi

cd $SPATH/geocode-glib-3.18.0
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libsecret-0.18.3
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

# 32 webkit need -O2 for libwebkit_Sources
# 64 webkit need -Os for libwebkit_Sources
# change in Gnumakefile.in
# static link only add up 140kb
mv $IPATH/lib/libstdc++.dll.a $IPATH/lib/libstdc++_s.a
if [ "$2" == "90" ]; then
if [ ! -d $SPATH/webkitgtk-2.2.8/$2-$CPUARCH ];then mkdir $SPATH/webkitgtk-2.2.8/$2-$CPUARCH; fi
cd $SPATH/webkitgtk-2.2.8/$2-$CPUARCH
../configure $triplet --prefix=$IPATH --with-target=win32 --disable-webgl LDFLAGS="$LDFLAGS -Wl,--no-keep-memory" CXXFLAGS="$CXXFLAGS -DUSE_PTHREADS -DWTF_USE_PTHREADS" $INTROSPECT
make clean
set +e
if [ ! -f libwebkit2gtk-3.0.la ]; then make $PJOBS; fi
if [ ! -f libwebkit2gtk-3.0.la ]; then make $PJOBS; fi
if [ ! -f libwebkit2gtk-3.0.la ]; then make $PJOBS; fi
if [ ! -f libwebkit2gtk-3.0.la ]; then make $PJOBS; fi
if [ ! -f libwebkit2gtk-3.0.la ]; then make $PJOBS; fi
set -e
make install
rm $IPATH/lib/*.la
else
cd $SPATH/webkitgtk-2.2.8/90-$CPUARCH
if [ -f libwebkit2gtk-3.0.la ]; then
sed --in-place -e "s;LDFLAGS = -m$CPUARCH -vcr90;LDFLAGS = -m$CPUARCH -vcr$2;" -e "s;prefix = /e/rtvc90-$CPUARCH;prefix = $IPATH;" -e "s;CXX = g++ -m$CPUARCH -vcr90;CXX = g++ -m$CPUARCH -vcr$2;" -e "s;G_IR_COMPILER = e:/rtvc90-$CPUARCH;G_IR_COMPILER = $IPATH;" -e "s;G_IR_GENERATE = e:/rtvc90-$CPUARCH;G_IR_GENERATE = $IPATH;" -e "s;G_IR_SCANNER = e:/rtvc90-$CPUARCH;G_IR_SCANNER = $IPATH;" GNUmakefile
sed --in-place -e "s;-lmsvcr90;-lmsvcr$2;g" -e "s; -vcr90 ; -vcr100 ;" -e "s;d:/moluccas/gcc48/bin/../lib/gcc/i686-w64-mingw32/4.8.5/../../../../i686-w64-mingw32/lib/../lib$MULTILIB/vc90dllman.o;;" libtool
rm libjavascriptcoregtk-3.0.la libwebkit2gtk-3.0.la libwebkitgtk-3.0.la
fi
make install
rm $IPATH/lib/*.la
fi
mv $IPATH/lib/libstdc++_s.a $IPATH/lib/libstdc++.dll.a

:<<"XXXX"
cd $SPATH/hyphen-2.8.8
configure --disable-shared --enable-static
make clean
make $PJOBS install 
rm $IPATH/lib/*.la

if [ ! -d $SPATH/webkitgtk-2.10.0/mingw ]; then
mkdir $SPATH/webkitgtk-2.10.0/mingw
fi
export PATH=$SPATH/webkitgtk-2.10.0/mingw/bin:$PATH
cd $SPATH/webkitgtk-2.10.0/mingw
#if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
#cmake -G "MSYS Makefiles" -DENABLE_ACCELERATED_2D_CANVAS=ON -DUSE_SYSTEM_MALLOC=ON -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel -DPORT=GTK ..
#make clean
set +e
make $PJOBS
if [ ! -f bin/libwebkit2gtk-4.0.dll ]; then make $PJOBS; fi
if [ ! -f bin/libwebkit2gtk-4.0.dll ]; then make $PJOBS; fi
if [ ! -f bin/libwebkit2gtk-4.0.dll ]; then make $PJOBS; fi
if [ ! -f bin/libwebkit2gtk-4.0.dll ]; then make $PJOBS; fi
if [ ! -f bin/libwebkit2gtk-4.0.dll ]; then make $PJOBS; fi
if [ ! -f bin/libwebkit2gtk-4.0.dll ]; then make $PJOBS; fi
set -e
make install
export PATH=$(echo $PATH | sed -e "s;$SPATH/webkitgtk-2\.10\.0/mingw/bin:;;")

cd $SPATH/libproxy-0.4.11/
# gir need recompile
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DWITH_WEBKIT3=ON -DCMAKE_INSTALL_PREFIX=$IPATH  -DCMAKE_BUILD_TYPE=MinSizeRel
make clean
make $PJOBS install
cp libproxy-1.0.pc $IPATH/lib/pkgconfig/
if [ "$CROSSX" != "1" ]; then
cp libproxy/Libproxy-1.0.gir $IPATH/share/gir-1.0/
cp libproxy/Libproxy-1.0.typelib $IPATH/lib/girepository-1.0/
fi
cp libproxy/CMakeFiles/libproxy.dir/objects.a $IPATH/lib/libproxy.a
cp libmodman/libmodman.a $IPATH/lib/libmodman.a
mv $IPATH/liblibproxy.dll.a $IPATH/lib/libproxy.dll.a
mv $IPATH/libproxy.dll $IPATH/bin/libproxy.dll
mv $IPATH/proxy.exe $IPATH/bin/proxy.exe
XXXX

cd $SPATH/curl-7.43.0
configure --with-winssl --with-ca-bundle=curl-ca-bundle.crt --disable-debug --disable-gopher --disable-telnet --disable-ldap --disable-static --enable-shared --without-ssl --with-libidn --without-librtmp --without-polarssl --enable-threaded-resolver --disable-imap --disable-pop3 --disable-rtsp --disable-ares --disable-manual --enable-sspi --with-libssh2 --disable-dict --enable-ipv6 LIBS=-liconv
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#c++
cd $SPATH/poppler-0.38.0
configure --enable-zlib --enable-libcurl --enable-libopenjpeg=openjpeg2 --with-font-configuration=fontconfig --disable-poppler-cpp CXXFLAGS="$CXXFLAGS -DSPLASH_CMYK" CFLAGS="$CFLAGS -DSPLASH_CMYK" $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la
rm $IPATH/bin/libpoppler-??.dll
cd glib
$CXX -shared $LDFLAGS .libs/*.o ../poppler/.libs/libpoppler-cairo.a ../poppler/.libs/libpoppler.a -lgio-2.0 -lgobject-2.0 -lglib-2.0 -lintl -lcairo -lfontconfig -lfreetype -ljpeg -lpng16 -ltiff -llcms2 -lopenjp2 -lz -Wl,--enable-auto-import -o $IPATH/bin/libpoppler-glib-8.dll -Wl,--out-implib,$IPATH/lib/libpoppler-glib.dll.a
cp $IPATH/lib/libpoppler-glib.dll.a $IPATH/lib/libpoppler.dll.a

cd $SPATH/discident-glib
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gupnp-igd-0.2.4
configure --disable-static LIBS=-lws2_32 $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libnice-0.1.13
# gir missing shared-library
configure --enable-compile-warnings=minimum --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd  $SPATH/farstream-0.2.7
configure $INTROSPECT LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

if [ -d $IPATH/include/libavcodec ]; then rm -rdf $IPATH/include/libavcodec; fi
if [ -d $IPATH/include/libavformat ]; then rm -rdf $IPATH/include/libavformat; fi
if [ -d $IPATH/include/libavutil ]; then rm -rdf $IPATH/include/libavutil; fi
cd $SPATH/gst-libav-1.6.1
# dont use --enable-small
if [ "$MULTILIB" == "64" ]; then
configure --with-libav-extra-configure="--disable-runtime-cpudetect --disable-sse42 --disable-sse4 --disable-ssse3 --disable-sse3 --optflags=-Os" CFLAGS="$CFLAGS -Os"
else
configure --with-libav-extra-configure="--disable-runtime-cpudetect --disable-sse42 --disable-sse4 --disable-ssse3 --disable-sse3 --disable-sse2 --optflags=-Os" CFLAGS="$CFLAGS -Os"
fi
make clean
make $PJOBS install
cd gst-libs/ext/libav
make install

cd $SPATH/gegl-0.3.0
if [ "$CROSSX" == "1" ]; then
configure --disable-static --enable-workshop $INTROSPECT --disable-gtk-doc-html --disable-gtk-doc --disable-docs CFLAGS="$CFLAGS -O2" LIBS="-lstdc++ -ljpeg"
else
configure --disable-static --enable-workshop --disable-gtk-doc-html --disable-gtk-doc --disable-docs $INTROSPECT CFLAGS="$CFLAGS -O2" LIBS="-lstdc++ -ljpeg"
fi
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/wavpack-4.70.0
configure --disable-shared --enable-mmx
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libcaca-0.99.beta19
configure --enable-static --disable-shared --disable-java --disable-ruby --disable-cxx --disable-csharp --disable-python --disable-doc CPPFLAGS="$CPPFLAGS -DCACA_STATIC"
make clean
make $PJOBS install
rm $IPATH/lib/*.la
:<<"XXXX"
cd $SPATH/boost_1_55_0
b2 --prefix=$GCC_LOC/$GCC_TRI --libdir=$GCC_LOC/$GCC_TRI/lib$MULTILIB --without-python --without-mpi --disable-icu --layout=system variant=release link=static runtime-link=static threading=multi toolset=gcc optimization=space address-model=$CPUARCH clean
b2 --prefix=$GCC_LOC/$GCC_TRI --libdir=$GCC_LOC/$GCC_TRI/lib$MULTILIB --without-python --without-mpi --disable-icu --layout=system variant=release link=static runtime-link=static threading=multi toolset=gcc optimization=space address-model=$CPUARCH cflags="$CFLAGS" cxxflags="$CXXFLAGS -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-local-typedefs -std=c++11" $PJOBS install
XXXX

cd $SPATH/taglib-1.9.1
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel -DENABLE_STATIC=ON
make clean
make $PJOBS install
#if [ ! -d $IPATH/include/taglib ]; then mkdir $IPATH/include/taglib; fi
#cp taglib/Headers/*.h bindings/c/Headers/*.h $IPATH/include/taglib
#$CXX -shared -o $IPATH/bin/libtag.dll -Wl,--whole-archive bindings/c/libtag_c.a -Wl,--no-whole-archive taglib/libtag.a $LDFLAGS -lz -Wl,--out-implib,$IPATH/lib/libtag.dll.a
#cp $IPATH/lib/libtag.dll.a $IPATH/lib/libtag_c.dll.a
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${exec_prefix}/include
Name: TagLib
Description: Audio meta-data library
Requires: zlib
Version: 1.9.1
Libs: -L${libdir} -ltag
Cflags: -I${includedir}/taglib -DTAGLIB_STATIC
' > $IPATH/lib/pkgconfig/taglib.pc
#cp $IPATH/lib/pkgconfig/taglib.pc $IPATH/lib/pkgconfig/taglib_c.pc

cd $SPATH/fftw-3.3.3
if [ "$MULTILIB" == "64" ]; then
configure --enable-sse2 --with-our-malloc --disable-fortran --disable-shared
make clean
make $PJOBS install
configure --enable-sse2 --with-our-malloc --enable-single --disable-fortran --disable-shared
make clean
make $PJOBS install
else
configure --with-our-malloc --disable-fortran --disable-shared
make clean
make $PJOBS install
configure --with-our-malloc --enable-single --disable-fortran --disable-shared
make clean
make $PJOBS install
fi
rm $IPATH/lib/*.la
$CC $LDFLAGS -shared -o $IPATH/bin/libfftw3.dll -Wl,--whole-archive $IPATH/lib/libfftw3.a $IPATH/lib/libfftw3f.a -Wl,--no-whole-archive -Wl,--out-implib,$IPATH/lib/libfftw3.dll.a
cp $IPATH/lib/libfftw3.dll.a $IPATH/lib/libfftw3f.dll.a

cd $SPATH/speex
configure --with-fft=smallft --enable-static --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd  $SPATH/libshout-2.3.1
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd  $SPATH/libdv-1.0.0
configure --disable-shared --disable-xv --disable-asm --disable-gtk --without-x CFLAGS="$CFLAGS -D_POSIX_C_SOURCE"
cd libdv
make clean
make $PJOBS install
rm $IPATH/lib/*.la
cp ../libdv.pc $IPATH/lib/pkgconfig/

cd $SPATH/libcdio-0.93
configure --enable-static --disable-shared --without-cdda-player --disable-cxx --disable-cpp-progs
make clean
make $PJOBS install
rm $IPATH/lib/*.la

if [ ! -d $SPATH/eigen3/mingw ]; then
mkdir $SPATH/eigen3/mingw
fi
cd $SPATH/eigen3/mingw
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=Release ..
make install

cd $SPATH/tbb40_20120613oss/src
set +e
if [ "$MULTILIB" == "64" ]; then
rm -rdf $SPATH/tbb40_20120613oss/build/windows_intel64_gcc_mingw_release/
mingw32-make compiler=gcc arch=intel64 runtime=mingw tbb_os=windows release
cd $SPATH/tbb40_20120613oss/build/windows_intel64_gcc_mingw_release
else
rm -rdf $SPATH/tbb40_20120613oss/build/windows_ia32_gcc_mingw_release/
mingw32-make compiler=gcc arch=ia32 runtime=mingw tbb_os=windows release
cd $SPATH/tbb40_20120613oss/build/windows_ia32_gcc_mingw_release
fi
set -e
ar cru $IPATH/lib/libtbb.a concurrent_hash_map.o concurrent_queue.o concurrent_vector.o dynamic_link.o itt_notify.o cache_aligned_allocator.o pipeline.o queuing_mutex.o queuing_rw_mutex.o reader_writer_lock.o spin_rw_mutex.o spin_mutex.o critical_section.o task.o tbb_misc.o tbb_misc_ex.o mutex.o recursive_mutex.o condition_variable.o tbb_thread.o concurrent_monitor.o semaphore.o private_server.o rml_tbb.o task_group_context.o governor.o market.o arena.o scheduler.o observer_proxy.o tbb_statistics.o tbb_main.o concurrent_vector_v2.o concurrent_queue_v2.o spin_rw_mutex_v2.o task_v2.o
ranlib $IPATH/lib/libtbb.a
ar cru $IPATH/lib/libtbbmalloc.a backend.o large_objects.o backref.o  tbbmalloc.o  itt_notify_malloc.o frontend.o
ranlib $IPATH/lib/libtbbmalloc.a
ar cru $IPATH/lib/libtbbmalloc_proxy.a proxy.o tbb_function_replacement.o
ranlib $IPATH/lib/libtbbmalloc_proxy.a
cp -a $SPATH/tbb40_20120613oss/include/tbb $IPATH/include/

if [ ! -d $SPATH/OpenCV-2.4.11/mingw ]; then mkdir $SPATH/OpenCV-2.4.11/mingw; fi
cd $SPATH/OpenCV-2.4.11/mingw
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles"  -DCMAKE_CXX_COMPILER=$GCC_LOC/bin/g++.exe -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_SHARED_LIBS=OFF -DBUILD_DOCS=OFF -DWITH_TBB=ON -DWITH_PNG=OFF -DWITH_JASPER=OFF -DWITH_JPEG=OFF -DENABLE_FAST_MATH=ON -DWITH_OPENEXR=OFF -DWITH_FFMPEG=OFF -DWITH_TIFF=OFF -DBUILD_opencv_python=OFF ..
make clean
make $PJOBS install
if [ -f $IPATH/x64/mingw/staticlib/OpenCVConfig.cmake ]; then
set +e
mv -f $IPATH/x64/mingw/staticlib/*.a $IPATH/lib/
rm -rdf $IPATH/x64/
set -e
fi
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir_old=${prefix}/include/opencv
includedir_new=${prefix}/include
Name: OpenCV
Description: Open Source Computer Vision Library
Version: 2.4.11
Requires: 
Cflags: -I${includedir_old} -I${includedir_new}
Libs: -lopencv_contrib2411 -lopencv_legacy2411 -lopencv_ml2411 -lopencv_stitching2411 -lopencv_ts2411 -lopencv_videostab2411 -lopencv_gpu2411 -lopencv_nonfree2411 -lopencv_objdetect2411 -lopencv_calib3d2411 -lopencv_photo2411 -lopencv_video2411 -lopencv_features2d2411 -lopencv_highgui2411 -lopencv_flann2411 -lopencv_imgproc2411 -lopencv_core2411 -lwinmm -lavicap32 -lavifil32 -lmsvfw32 -lole32 -lgdi32 -lcomctl32 -ltbb -lws2_32 -lz
' > $IPATH/lib/pkgconfig/opencv.pc

cd $SPATH/libsamplerate-0.1.8
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libsndfile-1.0.25
configure --disable-shared --disable-external-libs
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libvpx-1.5.0
if [ "$MULTILIB" == "64" ]; then 
./configure --target=x86_64-win64-gcc --disable-shared --disable-unit-tests --disable-examples --enable-vp8 --enable-vp9 --disable-runtime-cpu-detect --disable-sse3 --disable-ssse3 --disable-sse4_1 --disable-avx --disable-avx2 --enable-small --enable-multithread --enable-multi-res-encoding --enable-postproc --enable-vp9-postproc --prefix=$IPATH
else
./configure --disable-shared --disable-unit-tests --disable-examples --enable-vp8 --enable-vp9 --disable-runtime-cpu-detect --disable-sse2 --disable-sse3 --disable-ssse3 --disable-sse4_1 --disable-avx --disable-avx2 --enable-multithread --enable-small --enable-multi-res-encoding --enable-postproc --enable-vp9-postproc --prefix=$IPATH
fi
make clean
make $PJOBS install

cd $SPATH/jack2-1.9.10/windows
$CXX -I. -I../common -I../common/jack $CXXFLAGS -Wall -DWIN32 -DNDEBUG -D_WINDOWS -D_MBCS -D_USRDLL -DREGEX_MALLOC -DSTDC_HEADERS -D__SMP__ -DJACK_MONITOR -DHAVE_CONFIG_H -c ../common/JackAPI.cpp ../common/JackActivationCount.cpp ../common/JackAudioPort.cpp ../common/JackClient.cpp ../common/JackConnectionManager.cpp ../common/JackDebugClient.cpp ../common/JackEngineControl.cpp ../common/JackEngineProfiling.cpp ../common/JackError.cpp ../common/JackException.cpp ../common/JackFrameTimer.cpp ../common/JackGenericClientChannel.cpp ../common/JackGlobals.cpp ../common/JackGraphManager.cpp ../common/JackLibAPI.cpp ../common/JackLibClient.cpp ../common/JackMessageBuffer.cpp ../common/JackMidiAPI.cpp ../common/JackMidiPort.cpp ../common/JackPort.cpp ../common/JackPortType.cpp ../common/JackShmMem.cpp ../common/JackTools.cpp ../common/JackTransportEngine.cpp JackMMCSS.cpp JackWinMutex.cpp JackWinNamedPipe.cpp JackWinNamedPipeClientChannel.cpp JackWinProcessSync.cpp JackWinSemaphore.cpp JackWinServerLaunch.cpp JackWinThread.cpp
$CC -I. -I../common -I../common/jack $CFLAGS -Wall -DWIN32 -DNDEBUG -D_WINDOWS -D_MBCS -D_USRDLL -DREGEX_MALLOC -DSTDC_HEADERS -D__SMP__ -DJACK_MONITOR -DHAVE_CONFIG_H -c JackWinTime.c ../common/ringbuffer.c ../common/shm.c
windres -O coff -o libjack.o libjack.rc
$CXX -shared -o $IPATH/bin/libjack.dll *.o $LDFLAGS -Wl,--out-implib,$IPATH/lib/libjack.dll.a -lregex -lpsapi -lwinmm
#ar cru $IPATH/lib/libjack.a *.o
#ranlib $IPATH/lib/libjack.a
cp -a ../common/jack $IPATH/include/
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${exec_prefix}/include
server_libs= -ljackserver
Name: jack2
Description: the Jack Audio Connection Kit: a low-latency synchronous callback-based media server
Version: 1.9.10
Libs: -ljack
Cflags: 
' > $IPATH/lib/pkgconfig/jack.pc

cd $SPATH/aalib-1.4.0
export LIBS=-lws2_32
configure --enable-static --disable-shared
make clean
make $PJOBS install
unset LIBS

cd $SPATH/json-c-0.12
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libltdl
configure --disable-shared
make clean
make $PJOBS install
cp -a ltdl.h libltdl $IPATH/include/
cp .libs/libltdlc.a $IPATH/lib/libltdl.a

cd $SPATH/pulseaudio-6.0
configure --disable-shared --enable-static --enable-static-bins --enable-force-preopen --disable-gconf --disable-avahi --disable-dbus  --disable-systemd-daemon --disable-default-build-tests --disable-tests --disable-bluez4 --disable-bluez5 --disable-openssl --without-speex --without-fftw LIBS="-lregex -ldl"
make clean
make $PJOBS install
rm $IPATH/lib/*.la $IPATH/lib/pulseaudio/*.la

cd $SPATH/gst-plugins-good-1.6.1
configure --disable-static --enable-experimental CPPFLAGS="$CPPFLAGS -DCACA_STATIC" LIBS="-logg -lz"
make clean
make $PJOBS install
cd docs/plugins
make install

cd $SPATH/clutter-gst-3.0.14
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la
mv $IPATH/lib/gstreamer-1.0/libgstclutter-3.0.dll $IPATH/lib/gstreamer-1.0/libgstclutter.dll

cd $SPATH/a52dec-0.7.4
configure --disable-shared #CFLAGS="$CFLAGS -fno-inline"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libmpeg2-0.5.1
configure --disable-accel-detect --disable-sdl --disable-shared #CFLAGS="$CFLAGS -fno-inline"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/opencore-amr
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libmad-0.15.1b
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libdvdread-4.2.1
configure --disable-shared LIBS=-ldl
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/lame-3.99.5
configure --disable-shared --disable-decoder --enable-nasm  --disable-frontend
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/twolame-0.3.12
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/x264-snapshot-20141218-2245-stable
configure --enable-static CFLAGS="$CFLAGS -O2"
make clean
make $PJOBS install

cd $SPATH/libsidplay-1.36.59
configure --disable-shared --prefix=$IPATH
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gst-plugins-ugly-1.6.1
configure --disable-static --enable-experimental LIBS=-ldl
make clean
make $PJOBS install
cd docs/plugins
make install

cd $SPATH/gst-validate-1.6.0
configure PYTHON=python27$MULTILIB
make clean
make $PJOBS install

cd $SPATH/gstreamer-editing-services-1.6.1
configure --with-gtk=3.0 $INTROSPECT
make clean
make $PJOBS install
cd docs/libs
make install
rm $IPATH/lib/*.la

cd $SPATH/gst-rtsp-server-1.6.1
configure $INTROSPECT --disable-tests
make clean
make $PJOBS install
cd docs/libs
make install
rm $IPATH/lib/*.la

cd $SPATH/clutter-imcontext-0.1.6
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/clutter-gesture-0.0.2.1
configure --disable-shared
make clean
make $PJOBS 
ar cru clutter-gesture/.libs/libcluttergesture-0.0.2.a engine/*.o
make install
rm $IPATH/lib/*.la

cd $SPATH/mx-1.4.7
configure --disable-gtk-widgets --with-winsys=none $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/graphviz-2.16.1
#no need to build everything
set +e
make distclean
set -e
configure --disable-shared --enable-static --disable-tcl --disable-java --disable-sharp --disable-perl --disable-ltdl
cd $SPATH/graphviz-2.16.1/lib/common
cp y.output.bak y.output
cp y.tab.c.bak y.tab.c
cp y.tab.h.bak y.tab.h
cp htmlparse.c.bak htmlparse.c
cp htmlparse.h.bak htmlparse.h
make $PJOBS install
cd $SPATH/graphviz-2.16.1/lib/pathplan
make $PJOBS install
cd $SPATH/graphviz-2.16.1/lib/cdt
make $PJOBS install
cd $SPATH/graphviz-2.16.1/lib/pack
make $PJOBS install
cd $SPATH/graphviz-2.16.1/lib/graph
make $PJOBS install
cd $SPATH/graphviz-2.16.1/lib/gvc
make $PJOBS install
ar cru $IPATH/lib/libgvc.a $SPATH/graphviz-2.16.1/lib/common/*.o
rm $IPATH/lib/*.la

cd $SPATH/mysql-connector-c-6.0.2
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_CXX_FLAGS="$CXXFLAGS -D_TIMESPEC_DEFINED=1" -DWITH_OPENSSL=ON -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS -D_TIMESPEC_DEFINED=1" -D_OPENSSL_VERSION=1.0.2d -DOPENSSL_LIBRARIES=$IPATH/lib -DOPENSSL_INCLUDE_DIR=$IPATH/include -DSSL_EAY=$IPATH/lib/libssl.dll.a -DLIB_EAY=$IPATH/lib/libcrypto.dll.a
make clean
make $PJOBS install
ar d $IPATH/lib/libmysqlclient.a adler32.c.obj compress.c.obj crc32.c.obj deflate.c.obj infback.c.obj inffast.c.obj inflate.c.obj inftrees.c.obj trees.c.obj zutil.c.obj
cp $IPATH/lib/libmysqlclient.a $IPATH/lib/libmysql.a
rm $IPATH/bin/mysql*.exe $IPATH/lib/liblibmysql.dll.a
cd $IPATH/include
if [ ! -d $IPATH/include/mysql ]; then mkdir $IPATH/include/mysql; fi
mv base64.h config-win.h decimal.h errmsg.h hash.h keycache.h lf.h myisampack.h mysql.h mysqld_error.h mysql_com.h mysql_time.h mysql_version.h mysys_err.h my_aes.h my_alarm.h my_alloc.h my_atomic.h my_attribute.h my_base.h my_bit.h my_bitmap.h my_charsets.h my_config.h my_dbug.h my_dir.h my_getopt.h my_global.h my_libwrap.h my_list.h my_md5.h my_net.h my_nosys.h my_no_pthread.h my_pthread.h my_stacktrace.h my_sys.h my_time.h my_tree.h my_trie.h my_uctype.h my_vle.h my_xml.h m_ctype.h m_string.h queues.h service_versions.h sha1.h sha2.h sql_common.h sslopt-case.h sslopt-longopts.h sslopt-vars.h thr_alarm.h thr_lock.h typelib.h t_ctype.h violite.h waiting_threads.h wqueue.h $IPATH/include/mysql/
cp -a mysys $IPATH/include/mysql/
rm -rdf mysys

cd $SPATH/wineditline-2.101
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_BUILD_TYPE=MinSizeRel
make clean
make -j2 install
cp lib$CPUARCH/libedit_static.a $IPATH/lib/libedit.a
cp lib$CPUARCH/libedit_static.a $IPATH/lib/libreadline.a
cp include/editline/readline.h $IPATH/include/
if [ ! -d $IPATH/include/readline ]; then
mkdir $IPATH/include/readline
fi
cp include/editline/readline.h $IPATH/include/readline/
echo '#include "readline.h"'> $IPATH/include/readline/history.h

cd $SPATH/heimdal-1.6rc2
configure --prefix=$IPATH --includedir=$IPATH/include/heimdal --disable-heimdal-documentation --enable-pthread-support --disable-mmap --disable-kcm --disable-ndbm-db --enable-littleendian --with-libedit --without-readline --with-libedit-lib=$IPATH/lib --with-libedit-include=$IPATH/include --with-sqlite --with-sqlite3-lib=$IPATH/lib --with-sqlite3-include=$IPATH/include LIBS="-lws2_32 -lshlwapi -lsecur32 -lsqlite3" --disable-afs-string-to-key
find . -name *.a -exec rm {} +
find . -name *.la -exec rm {} +
find . -name *.exe -exec rm {} +
find . -name *.lo -exec rm {} +
find . -name *.o -exec rm {} +
cd include
make $PJOBS install
cd ../lib
make $PJOBS V=1
make install
cd ../tools
make install
cp $IPATH/lib/libgssapi.dll.a $IPATH/lib/libgssapi32.dll.a
cp $IPATH/lib/libgssapi.dll.a $IPATH/lib/libroken.dll.a
cp $IPATH/lib/libgssapi.dll.a $IPATH/lib/libheimbase.dll.a
cp $IPATH/lib/libgssapi.dll.a $IPATH/lib/libcom_err.dll.a
cp $IPATH/lib/libgssapi.dll.a $IPATH/lib/libwind.dll.a
cp $IPATH/lib/libgssapi.dll.a $IPATH/lib/libasn1.dll.a
cp $IPATH/lib/libgssapi.dll.a $IPATH/lib/libheimntlm.dll.a
cp $IPATH/lib/libgssapi.dll.a $IPATH/lib/libkrb5.dll.a
rm $IPATH/lib/*.la

cd $SPATH/postgresql-9.3.5
# krb5/gssapi is just alternative on windows
configure --prefix=$IPATH --with-system-tzdata=/share/zoneinfo --with-libxml --with-libxslt --with-openssl --with-ldap --without-gssapi --without-krb5 CPPFLAGS="-I$IPATH/include -I$IPATH/include/heimdal" CFLAGS="$RTVER -Os -fno-lto" CXXFLAGS="$RTVER -Os -fno-lto"
cd $SPATH/postgresql-9.3.5/src/interfaces/libpq
make clean
set +e
make $PJOBS libpq.dll
make install -k
rm $IPATH/lib/libpq.*
ar cru $IPATH/lib/libpq.a *.o
ranlib $IPATH/lib/libpq.a
cp -a $SPATH/postgresql-9.3.5/src/include/libpq $IPATH/include/
cp libpq-events.h libpq-fe.h $IPATH/include/
cd $SPATH/postgresql-9.3.5/src/include/
cp pg_config_ext.h postgres_ext.h $IPATH/include/
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: libpq
Description: PostgreSQL libpq library
Url: http://www.postgresql.org/
Version: 9.3.5
Requires:
Requires.private:
Cflags: -I${includedir}
Libs: -L${libdir} -lpq -lgssapi -lcrypto -lwldap32 -lshfolder -lwsock32 -lws2_32 -lsecur32
' > $IPATH/lib/pkgconfig/libpq.pc
rm $IPATH/bin/libpq.dll
set -e

cd $SPATH/db-5.3.28/build_unix
../dist/configure $triplet --enable-smallbuild --enable-mingw --enable-sql --prefix=$IPATH CPPFLAGS="" CFLAGS="$CFLAGS -DSQLITE_ENABLE_COLUMN_METADATA"
make clean
make $PJOBS
make install_include 
make install_lib
rm $IPATH/lib/*.la

cd $SPATH/cyrus-sasl-2.1.26
set +e
make distclean
set -e
configure --with-gss_impl=heimdal --with-sqlite3=$IPATH --with-openssl CPPFLAGS="$CPPFLAGS -I$IPATH/include/heimdal" --without-saslauthd --without-authdaemond --enable-sql --enable-ntlm --enable-login --enable-srp --enable-srp-setpass
set +e
make
set -e
$CC -shared -o $IPATH/bin/libsasl2.dll -Wl,--whole-archive lib/.libs/libsasl2.a -Wl,--no-whole-archive -L./plugins/.libs -L$IPATH/lib -lws2_32 -ldl -lanonymous -lcrammd5 -ldigestmd5 -lgssapiv2 -lgs2 -llogin -lotp -lplain -lsrp -lsasldb -lntlm -lsql -lcrypto -lsqlite3 -lgssapi -lws2_32 -ldb-5.3 -Wl,-s -Wl,--out-implib,$IPATH/lib/libsasl2.dll.a
cp libsasl2.pc $IPATH/lib/pkgconfig/
cp $IPATH/lib/libsasl2.dll.a $IPATH/lib/libsasl.dll.a
cd include
make install

cd $SPATH/openldap-2.4.38
configure --disable-shared --without-cyrus-sasl --disable-slapd --with-tls=openssl
make clean
make $PJOBS 
manifest
make install
rm $IPATH/lib/*.la

cd $SPATH/geglgit/gegl-gtk
configure --without-vala $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gtkspell3-3.0.3
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la
:<<"XXXX"
cd $SPATH/gtkdatabox
configure --disable-static --enable-glade $INTROSPECT 
make clean
make $PJOBS install
rm $IPATH/lib/*.la
cd glade
$CC -shared .libs/libgladedatabox_la-gladeui-databox.o -L$IPATH/gladeold/lib -lgladeui-2 -L$IPATH/lib -lgtk-3 -lgobject-2.0 -Wl,-s -o $IPATH/lib/glade/modules/libgladedataboxold.dll
XXXX
cd $SPATH/adg-0.8.0/build
../configure $triplet --prefix=$IPATH --disable-static $INTROSPECT
make clean
make $PJOBS
manifest
make install
rm $IPATH/lib/*.la

cd $SPATH/goocanvas-2.0.2
configure --disable-static --disable-python $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#cd $SPATH/libgnome-keyring-3.12.0
#configure $INTROSPECT
#make clean
#make $PJOBS install
#rm $IPATH/lib/*.la

cd $SPATH/sofia-sip-1.12.11
configure --disable-shared --enable-experimental --with-openssl LIBS="-lws2_32 -liphlpapi"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/phodav-2.0
configure --enable-static --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/lz4-r127
make clean
make all $PJOBS
cp lib/liblz4.a $IPATH/lib
cp lib/liblz4.pc $IPATH/lib/pkgconfig
cp lib/*.h $IPATH/include

cd $SPATH/libusb-1.0.19
configure --disable-static
make clean
make $PJOBS
manifest
make install
rm $IPATH/lib/*.la

cd $SPATH/usbredir-0.6
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgusb-0.2.6
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/colord-1.2.12
configure --disable-argyllcms-sensor --disable-static --disable-bash-completion --disable-examples --disable-polkit --disable-print-profiles --disable-sane --disable-session-example --disable-systemd-login --disable-udev --without-pic --with-systemdsystemunitdir=/tmp --with-udevrulesdir=/tmp
make clean
make $PJOBS install
rm $IPATH/lib/*.la
mv $IPATH/lib/bin/*private.dll $IPATH/lib/colord-sensors/

cd $SPATH/colord-gtk-0.1.26
configure --disable-static 
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/firebird-mingw-w64-2_5
configure --with-system-icu --disable-shared
make clean
if [ -f gen/jrd/version.res ]; then rm gen/jrd/version.res; fi
cd gen
make includes
make $PJOBS -f ../gen/Makefile.libfbstatic libfbstatic
make $PJOBS -f ../gen/Makefile.boot.gpre gpre_boot
make $PJOBS -f ../gen/Makefile.libfbclient libfbclient
if [ ! -d $IPATH/include/firebird ]; then mkdir $IPATH/include/firebird; fi
cp firebird/include/*.h $IPATH/include/firebird
cp firebird/lib/libfbclient.a $IPATH/lib/
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include/firebird
Name: fbclient
Description: Firebird client
Version: 2.5.3
Requires:
Libs: -L${libdir} -lfbclient -lmpr -lversion -lws2_32 -lole32 -lsupc++
Cflags: -I${includedir}'> $IPATH/lib/pkgconfig/fbclient.pc

cd $SPATH/libgda-5.2.2
#for firebird client use static stdc++
# too many hassle for cross compile...
if [ ! "$CROSSX" == "1" ]; then
configure --with-firebird --with-mdb --with-bdb=$IPATH --with-ldap=$IPATH --with-mysql=$IPATH --with-mysql-libdir-name=lib --with-bdb-libdir-name=lib --enable-json --with-graphviz --disable-system-mdbtools --with-gtksourceview --with-ui --with-goocanvas --with-libsoup --without-help LIBS="-lcrypto -lexpat -lz" $INTROSPECT --enable-gdaui-gi CFLAGS="$CFLAGS -DGVSTATIC"
make clean
make $PJOBS
manifest
make install
rm $IPATH/lib/*.la
fi

cd $SPATH/spice-protocol-0.12.10
configure
make $PJOBS install

cd $SPATH/spice-gtk-0.30
configure --enable-lz4 --with-audio=gstreamer --disable-werror $INTROSPECT LIBS="-lusb-1.0 -lxml2"
make clean
make $PJOBS install
make check
rm $IPATH/lib/*.la

cd $SPATH/gtk-vnc-0.5.4
configure --with-gtk=3.0 --without-pulseaudio --disable-vala $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/meanwhile-1.0.2
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/silc-toolkit-1.1.10
configure --disable-shared --disable-asm --with-win32
make clean
make $PJOBS install
cd lib
rm -rdf *.la .libs
make libsilcclient.a
make libsilc.a
cp .libs/*.a $IPATH/lib/

cd $SPATH/telepathy-glib-0.24.1
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/telepathy-logger-0.8.1
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/telepathy-farstream-0.6.2
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/telepathy-rakia-0.8.0
configure LIBS=-lws2_32
make clean
make install

cd $SPATH/telepathy-idle-0.2.0
configure LIBS=-lws2_32
make clean
make $PJOBS install

cd $SPATH/telepathy-gabble-0.18.2
configure --with-ca-certificates=curl-ca-bundle.crt --disable-Werror --with-tls=gnutls --disable-debug LIBS="-lforknt -lws2_32"
make clean
make $PJOBS install

cd $SPATH/telepathy-salut-0.8.1
echo '
prefix=
exec_prefix=${prefix}
libdir=${prefix}/lib
includedir=${prefix}/include
Name: Bonjour
Description: Bonjour DNS Responder
Version: 0.6.31
Libs: -ldns_sd
Cflags: 
' > $IPATH/lib/pkgconfig/libdns_sd.pc
set +e
make distclean
set -e
configure --with-backend=bonjour --disable-avahi-tests --disable-debug LIBS="-lforknt -lws2_32"
make $PJOBS install

cd $SPATH/game-music-emu-0.5.5/gme
echo '
#ifndef GME_TYPES_H
#define GME_TYPES_H
#define USE_GME_AY
#define USE_GME_GBS
#define USE_GME_GYM
#define USE_GME_HES
#define USE_GME_KSS
#define USE_GME_NSF
#define USE_GME_NSFE
#define USE_GME_SAP
#define USE_GME_SPC
#define USE_GME_VGM
#endif /* GME_TYPES_H */'>gme_types.h
$CXX $CXXFLAGS -I. -c *.cpp
ar cru $IPATH/lib/libgme.a *.o
ranlib $IPATH/lib/libgme.a
if [ ! -d $IPATH/include/gme ]; then mkdir $IPATH/include/gme; fi
cp gme.h $IPATH/include/gme/

cd $SPATH/libkate-0.3.8
configure --disable-shared --enable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/flite-1.4-release
configure --disable-shared --with-lex --with-vox --with-lang
set +e
make clean
set -e
make 
make install

cd $SPATH/libdvdnav-4.2.1
configure --disable-shared LIBS=-ldl
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/daala-c602bc3
configure --disable-shared --disable-unit-tests --disable-player
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libdca-0.0.5
configure --disable-shared #CFLAGS="$CFLAGS -fno-inline"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/chromaprint-1.2
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel -DBUILD_SHARED_LIBS=OFF -DWITH_FFTW3=OFF -DWITH_AVFFT=ON
make clean
make $PJOBS install
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: chromaprint
Description: Audio fingerprint library
Version: 1.0.0
Cflags: -I${includedir} -DCHROMAPRINT_NODLL
Libs: -L${libdir} -lchromaprint -lavcodec -lavutil -lstdc++
' > $IPATH/lib/pkgconfig/libchromaprint.pc

cd $SPATH/libofa-0.9.3
configure --enable-static --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/schroedinger
configure --enable-static --disable-shared --with-thread=pthread
cd $SPATH/schroedinger/schroedinger
make clean
make $PJOBS install
rm $IPATH/lib/*.la
cd $SPATH/schroedinger
cp schroedinger.pc $IPATH/lib/pkgconfig/
cp schroedinger.pc $IPATH/lib/pkgconfig/schroedinger-1.0.pc

cd $SPATH/libmimic-1.0.4
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/mjpegtools-2.1.0
configure --enable-static --disable-shared --without-libsdl --without-gtk --enable-simd-accel
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gsm
make clean
make lib/libgsm.a
cp -a $SPATH/gsm/inc/gsm $SPATH/gsm/inc/gsm.h $IPATH/include/
cp $SPATH/gsm/lib/libgsm.a $IPATH/lib/

cd $SPATH/faac-1.28
configure --enable-static --disable-shared LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/faad2-2.7
configure --enable-static --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/soundtouch
configure --enable-static --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/openal-soft-1.15.1
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DSSE=ON -DLIBTYPE=STATIC
make clean
make $PJOBS install

cd $SPATH/vo-aacenc-0.1.3
configure --enable-static --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

# AV False positive need -O2
cd $SPATH/vo-amrwbenc-0.1.3
configure --enable-static --disable-shared CFLAGS="$CFLAGS -O2"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/srtp
configure --enable-static --disable-shared
make clean
make
make uninstall
make install

cd $SPATH/spandsp-0.0.6
if [ -d $IPATH/lib64 ]; then rm -rdf $IPATH/lib64; fi
# consider to patch telephony.h ?
configure --libdir=$IPATH/lib --enable-static --disable-shared CFLAGS="$CFLAGS -DLIBSPANDSP_EXPORTS" CXXFLAGS="$CXXFLAGS -DLIBSPANDSP_EXPORTS"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/mpg123-1.16.0
configure --enable-static --disable-shared --with-audio=win32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/enca
configure --disable-shared --enable-static --disable-external
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/fribidi-0.19.6
configure --disable-shared --with-glib=no CFLAGS="$CFLAGS -Os"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libass-0.12.2
configure --disable-shared --enable-static --enable-enca
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#c++
cd $SPATH/libmodplug
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/rtmpdump-git/librtmp
make clean
make $PJOBS install prefix=$IPATH
rm $IPATH/bin/librtmp.* $IPATH/lib/librtmp.dll.a

cd $SPATH/libmms-0.6.2
configure --disable-shared --enable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/sbc-1.1
configure --disable-shared --enable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/neon-0.30.1
# using SSPI instead of GSSAPI
configure --disable-shared --disable-nls --without-gssapi --enable-threadsafe-ssl=posix --with-ssl=gnutls --with-ca-bundle=curl-ca-bundle.crt CPPFLAGS="$CPPFLAGS $(pkg-config --cflags glib-2.0) -DUSE_GETADDRINFO -DHAVE_SSPI -DNE_HAVE_IPV6 -DNE_HAVE_LFS"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/fluidsynth
configure --disable-static --disable-pulse-support --without-readline --disable-libsndfile-support --disable-dbus-support
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libaerial-0.1.0
# gir missing shared-library
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/zbar-0.10
configure --disable-shared --enable-static --without-python --without-gtk --without-jpeg --without-imagemagick --without-qt 
make clean
if [ -f zbarcam/zbarcam-rc.o ]; then
rm zbarcam/zbarcam-rc.o
fi
make $PJOBS install
rm $IPATH/lib/*.la

# FIXME: gir generation failed
cd $SPATH/graphene-1.2.10
#configure --disable-gcc-vector --disable-sse2 --enable-debug=minimum
if [ "$MULTILIB" == "64" ]; then 
configure --enable-debug=minimum CFLAGS="$CFLAGS -O2" --enable-introspection=no
else
configure --enable-debug=minimum --disable-gcc-vector --disable-sse2 CFLAGS="$CFLAGS -O2" --enable-introspection=no
fi
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/wildmidi-0.2.3.5
configure --disable-static --enable-shared --disable-werror CFLAGS="$CFLAGS -DWILDMIDI_BUILD"
make clean
make install
rm $IPATH/lib/*.la

cd $SPATH/libbs2b-3.1.0
configure
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#begin c++
cd $SPATH/OpenNI2-2.2-beta2
mv $IPATH/lib/libstdc++.dll.a $IPATH/lib/libstdc++_s.a
make clean
make $PJOBS ALLOW_WARNINGS=1 SSE_GENERATION=2 core
if [ -d $IPATH/include/openni2 ]; then
rm -rdf $IPATH/include/openni2
fi
cp -a Include/ $IPATH/include/openni2
cp ThirdParty/PSCommon/XnLib/Bin/x86-Release/libXnLib.a $IPATH/lib
set +e
mkdir -p $IPATH/lib/gstreamer-1.0/OpenNI2/Drivers
set -e
ar cru $IPATH/lib/libopenni2.a Bin/Intermediate/x86-Release/libOpenNI2.dll/x*.o Bin/Intermediate/x86-Release/libOpenNI2.dll/o*.o
ranlib $IPATH/lib/libopenni2.a
$CXX -shared $LDFLAGS -o Bin/x86-Release/OpenNI2/Drivers/libPS1080.dll Bin/Intermediate/x86-Release/libPS1080.dll/x*.o Bin/Intermediate/x86-Release/libPS1080.dll/y*.o Bin/Intermediate/x86-Release/libPS1080.dll/u*.o Bin/Intermediate/x86-Release/libPS1080.dll/b*.o Bin/x86-Release/libDepthUtils.a ThirdParty/PSCommon/XnLib/Bin/x86-Release/libXnLib.a -ljpeg -lsetupapi -lws2_32
$CXX -shared $LDFLAGS -o Bin/x86-Release/OpenNI2/Drivers/libOniFile.dll Bin/Intermediate/x86-Release/libOniFile.dll/x*.o Bin/Intermediate/x86-Release/libOniFile.dll/p*.o Bin/Intermediate/x86-Release/libOniFile.dll/d*.o ThirdParty/PSCommon/XnLib/Bin/x86-Release/libXnLib.a -ljpeg -lsetupapi -lws2_32
cp Bin/x86-Release/OpenNI2/Drivers/*.dll $IPATH/lib/gstreamer-1.0/OpenNI2/Drivers
echo '
prefix=
exec_prefix=${prefix}
libdir=${prefix}/lib
includedir=${prefix}/include/openni2
Name: OpenNI2
Description: OpenNI2
Version: 2.2
Libs: -lopenni2 -lxnlib -ljpeg
Cflags: -I${includedir}
' > $IPATH/lib/pkgconfig/libopenni2.pc
mv $IPATH/lib/libstdc++_s.a $IPATH/lib/libstdc++.dll.a

cd $SPATH/libde265-1.0.2
if [ "$MULTILIB" == "64" ]; then 
configure --disable-shared --disable-dec265 --disable-sherlock265
else
configure --disable-shared --disable-dec265 --disable-sherlock265 CFLAGS="$CFLAGS -O2"
fi
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/x265-1.7/source
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DENABLE_SHARED=OFF -DWINXP_SUPPORT=ON -DENABLE_CLI=OFF
make clean
make $PJOBS install

cd $SPATH/openh264-1.4.0
make clean
if [ "$MULTILIB" == "64" ]; then 
make ENABLE64BIT=Yes $PJOBS
else
make ENABLE64BIT=No $PJOBS
fi
make install PREFIX=$IPATH
rm $IPATH/lib/libopenh264.dll.a $IPATH/bin/libopenh264.dll

cd $SPATH/xapian-core-1.2.21
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la
#end c++

cd $SPATH/xapian-glib-2.4.0
configure --disable-static LIBS="-lxapian -lz -lstdc++ -lws2_32 -lrpcrt4"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gst-plugins-bad-1.6.1
mv $IPATH/lib/libstdc++.dll.a $IPATH/lib/libstdc++_s.a
configure --disable-static --enable-experimental $INTROSPECT
make clean
make $PJOBS 
make install
rm $IPATH/lib/*.la
mv $IPATH/lib/libstdc++_s.a $IPATH/lib/libstdc++.dll.a

cd $SPATH/devhelp-3.16.1
configure
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/pcre-8.35
configure --disable-shared --disable-cpp --enable-pcre16 --enable-pcre32 --enable-unicode-properties
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libtimezonemap-0.4.4
configure --disable-static
make clean
make install
rm $IPATH/lib/*.la

cd $SPATH/libgit2-glib-0.23.6
configure --disable-vala --disable-python
make clean
if [ "$CROSSX" == "1" ]; then
cd libgit2-glib
make install-libLTLIBRARIES $PJOBS
make install-headerDATA
cd ..
make install-pkgconfigDATA
cd docs
make install
else
make $PJOBS install
fi
rm $IPATH/lib/*.la

cd $SPATH/gexiv2-0.10.3
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/nspr-4.10.2
export _CPPFLAGS=$CPPFLAGS
export _CFLAGS=$CFLAGS
export _LDFLAGS=$LDFLAGS
unset CPPFLAGS
unset LDFLAGS
export CFLAGS="$CFLAGS -DNSPR_STATIC"
if [ -f config.cache ]; then rm -f config.cache; fi
configure --enable-win32-target=WIN95 --disable-debug --disable-debug-symbols --enable-optimize=-Os
make clean
make $PJOBS
manifest
make install
cd $IPATH/lib
rm nspr4.dll plds4.dll plc4.dll ../bin/nspr-config
#rm nspr4.dll* plds4.dll* plc4.dll*
mv nspr4_s.a libnspr4.a
mv plds4_s.a libplds4.a
mv plc4_s.a libplc4.a
mv nspr4.dll.a libnspr4_s.dll.a
mv plds4.dll.a libplds4_s.dll.a
mv plc4.dll.a libplc4_s.dll.a
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include/nspr
Name: NSPR
Description: The Netscape Portable Runtime
Version: 4.10.2
Cflags: -I${includedir} -DNSPR_STATIC
Libs: -L${libdir} -lplds4 -lplc4 -lnspr4 -lwinmm -lws2_32
' > $IPATH/lib/pkgconfig/nspr.pc
export CPPFLAGS=$_CPPFLAGS
export LDFLAGS=$_LDFLAGS
export CFLAGS=$_CFLAGS
#$CC -shared -o $IPATH/bin/libnspr4.dll -Wl,--export-all-symbols -Wl,--allow-multiple-definition -Wl,--whole-archive $IPATH/lib/plds4_s.a $IPATH/lib/plc4_s.a $IPATH/lib/nspr4_s.a -Wl,--no-whole-archive $LDFLAGS -Wl,--out-implib,$IPATH/lib/libnspr4.dll.a -lwinmm -lws2_32
#cp $IPATH/lib/libnspr4.dll.a $IPATH/lib/libplds4.dll.a
#cp $IPATH/lib/libnspr4.dll.a $IPATH/lib/libplc4.dll.a

#c++
export PYTHON=python27
export CPP=cpp
export CXXCPP="gcc -E"
cd $SPATH/mozjs-24.2.0/js/src
if [ -f config.cache ]; then rm config.cache; fi
# pass -DENABLE_INTL_API and -licuuc to enable Intl but it crashed with GJS ????
configure --disable-debug --disable-debug-symbols --enable-optimize=-O2 --with-system-zlib --enable-system-ffi --enable-threadsafe --enable-system-ffi --with-system-zlib=$IPATH --disable-shared-js --disable-intl-api --with-nspr-libs="-L$IPATH/lib -lplds4 -lplc4 -lnspr4" --with-nspr-cflags="-I$IPATH/include/nspr -DNSPR_STATIC"
make clean
make $PJOBS 
make install
rm $IPATH/bin/js24-config
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: SpiderMonkey 24.2.0
Description: The Mozilla library for JavaScript
Version: 24.2.0
Requires: nspr,zlib,libffi
Cflags: -include ${includedir}/mozjs-24/js/RequiredDefines.h -I${includedir}/mozjs-24 -DSTATIC_JS_API
Libs: -L${libdir} -lmozjs-24 -lpsapi
' > $IPATH/lib/pkgconfig/mozjs-24.pc
unset PYTHON

cd $SPATH/gjs-1.44.0
mv $IPATH/lib/libstdc++.dll.a $IPATH/lib/libstdc++_s.a
set +e
make distclean
set -e
configure --prefix=$IPATH LIBS=-lforknt
make $PJOBS install
rm $IPATH/lib/*.la
if [ ! -d $IPATH/share/gjs-1.0 ]; then
mkdir $IPATH/share/gjs-1.0
fi
cp -a modules/overrides modules/tweener modules/*.js $IPATH/share/gjs-1.0/
mv $IPATH/lib/libstdc++_s.a $IPATH/lib/libstdc++.dll.a

cd $SPATH/gimo-master
if [ "$2" == "90" ]; then
list="27 31 32"
else
list="33 34"
fi
for i in $list; do
PYINC=`python$i$MULTILIB-config --cflags`
configure PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$IPATH/py$i/lib/pkgconfig" PYTHON=python$i$MULTILIB PYGOBJECT_CFLAGS="-I$IPATH/py$i/include/pygobject-3.0 $PYINC"  PYGOBJECT_LIBS=-lpython$i PYTHON_CONFIG=/bin/python$i$MULTILIB-config
make clean
make install
mv $IPATH/lib/gimo-plugins-1.0/pymodule-1.0.dll $IPATH/lib/gimo-plugins-1.0/pymodule-1.0$i.dll
rm $IPATH/lib/*.la
done

cd $SPATH/djvulibre-3.5.27
configure --disable-shared --enable-static --disable-desktopfiles  --disable-xmltools  LDFLAGS="$LDFLAGS -liconv"
make clean
make install
rm $IPATH/lib/*.la

cd $SPATH/cfitsio
if [ "$MULTILIB" == "64" ]; then
configure --enable-sse2 --disable-ssse3 --enable-reentrant
else
configure --disable-sse2 --disable-ssse3 --enable-reentrant
fi
make clean
make $PJOBS
ar cru lib/libcfitsio.a *.o
ranlib lib/libcfitsio.a
cp include/*.h $IPATH/include/
cp lib/*.a $IPATH/lib/
cp cfitsio.pc $IPATH/lib/pkgconfig/

cd $SPATH/matio
configure --disable-shared --enable-extended-sparse=yes --enable-mat73=yes
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/openslide-3.4.1
configure --enable-static --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH
$CC $CFLAGS -o $IPATH/bin/dcraw dcraw.c -DNODEPS $LDFLAGS -lws2_32

cd $SPATH/liblqr
configure --disable-shared --enable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#the only magick deps thats need stdc++
#cd $SPATH/libfpx-1.2.0.13
#make -f makefile.gcc clean
#cp fpxlib.h $IPATH/include
#cp obj/libfpx.a $IPATH/lib

cd $SPATH/ImageMagick-6.9.1-10
# configured as fallback for *8bit* image loader and vector-rasterizer and keep it LGPL friendly
configure --without-perl --without-wmf --without-fpx --without-gvc --without-djvu --with-fontconfig --with-freetype --without-magick-plus-plus --with-quantum-depth=8 --with-rsvg --without-lcms --without-fftw --disable-static CPPFLAGS="$CPPFLAGS -I$IPATH/include/libxml2" LIBS=-lws2_32
#if use fpx LIBS=-lws2_32-lole32 -lstdc++
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/vips-8.1.1
configure --without-fftw --without-python --disable-static $INTROSPECT CFLAGS="$CFLAGS -O2"
make clean
make install
rm $IPATH/lib/*.la

cd $SPATH/gmime-2.6.20
configure --disable-mono --disable-vala --disable-cryptography $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la
:<<"XXXX"
# messed up, gmp already linked into gnutls
cd $SPATH/mpfr-3.1.2
configure --enable-static --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la
XXXX
cd $SPATH/gnome-js-common-0.1
configure --disable-seed --disable-gjs
make install-pkgconfigDATA

cd $SPATH/seed-3.8.1
configure --disable-mpfr-module --disable-static --disable-os-module
make clean
if [ "$CROSSX" == "1" ]; then
set +e
make $PJOBS install -k
set -e
else
make $PJOBS install
fi
rm $IPATH/lib/*.la

cd $SPATH/GConf-3.2.6
configure --enable-gsettings-backend --disable-orbit $INTROSPECT LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/liboauth-1.0.3
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

if [ "$2" == "90" ]; then
cd $SPATH/libpeas-1.16.0
configure --enable-glade-catalog --enable-compile-warnings=minimum --enable-gtk --disable-python3 --enable-python2 PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$IPATH/py27/lib/pkgconfig" PYTHON2=/usr/bin/python27$MULTILIB PYTHON=/usr/bin/python27$MULTILIB PYTHON2_CONFIG=/bin/python27$MULTILIB-config
make clean
make $PJOBS install
mv $IPATH/lib/libpeas-1.0/loaders/libpythonloader.dll $IPATH/lib/libpeas-1.0/loaders/libpython27-loader.dll
rm $IPATH/lib/*.la
fi
# peas says 3.1 is obsolete
if [ "$2" == "90" ]; then
list="32"
else
list="33 34"
fi
for i in $list; do
cd $SPATH/libpeas-1.16.0
configure --enable-glade-catalog  --enable-compile-warnings=minimum --enable-gtk --disable-python2 --enable-python3 PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$IPATH/py$i/lib/pkgconfig" PYTHON=/usr/bin/python$i$MULTILIB PYTHON3_CONFIG=/usr/bin/python$i$MULTILIB-config
make clean
make $PJOBS install
mv $IPATH/lib/libpeas-1.0/loaders/libpython3loader.dll $IPATH/lib/libpeas-1.0/loaders/libpython$i-loader.dll
done

#need gcrypt
cd $SPATH/gcr-3.18.0
# need fix gir version 3.broken
configure --disable-static $INTROSPECT LDFLAGS="$LDFLAGS -Wl,--allow-multiple-definition"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

# TODO:  --enable-kerberos, need MIT shim for heimdal
# >=3.16 need wbkit2 4.0 lst working 3.14.x
cd $SPATH/gnome-online-accounts-3.14.4
configure --disable-static --enable-inspector --without-x --enable-compile-warnings=minimum --enable-schemas-compile $INTROSPECT
make clean
make $PJOBS 
make install
rm $IPATH/lib/*.la
:<<"XXXX"
# replaced by internal GTKGL, conflict
cd $SPATH/gtkglext3-master
configure --enable-win32-backend --enable-debug=minimum $INTROSPECT
make clean
make $PJOBS 
rm $IPATH/lib/*.la
XXXX
cd $SPATH/uhttpmock-0.4.0
configure --disable-static --disable-vala $INTROSPECT LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgdata-0.16.1
configure --disable-gnome --enable-compile-warnings=no $INTROSPECT LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libarchive-3.1.2
configure --without-xml2 --without-expat --without-openssl --enable-posix-regex-lib=libregex --without-nettle --disable-bsdcpio --without-lzo2 --disable-bsdtar  --disable-static --enable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgxps-0.2.3.2
set +e
rm -rdf $IPATH/include/libgxps
set -e
configure --disable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgweather-3.18.0
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgrss-0.7.0
configure --disable-static $INTROSPECT LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgepub-master
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/vala-0.30.0
echo '#define BUILD_VERSION "0.30.0"'> ccode/version.h
echo '#define BUILD_VERSION "0.30.0"'> vala/version.h
configure --disable-static --enable-silent-rules
make clean
make $PJOBS install
rm $IPATH/lib/*.la
#cp /local/lib/pkgconfig/libvala-0.22.pc /local/lib/pkgconfig/libvala-0.20.pc
#cp /local/lib/pkgconfig/libvala-0.24.pc /local/lib/pkgconfig/libvala-0.20.pc
#cp /local/lib/pkgconfig/libvala-0.24.pc /local/lib/pkgconfig/libvala-0.22.pc

cd $SPATH/gxml-0.4.0
# gir missing shared-library
configure --disable-static  --disable-docs $INTROSPECT
find . -name *.lo -exec rm {} +
find . -name *.exe -exec rm {} +
find . -name *.o -exec rm {} +
echo "">gxml/gxml_0_4_la_vala.stamp
make install
rm $IPATH/lib/*.la

cd $SPATH/twitter-glib-0.9.8
configure --disable-static --disable-maintainer-flags $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#export FREEBL_NO_DEPEND=1
#export FREEBL_LOWHASH=1
export NSS_USE_SYSTEM_SQLITE=1
export BUILD_OPT=1
export HOST="localhost"
export DOMSUF=" "
export USE_IP=TRUE
export USE_STATIC_LIBS=1
export IP_ADDRESS="127.0.0.1"
export NS_USE_GCC=1
export OPT_CODE_SIZE=1
export ALLOW_OPT_CODE_SIZE=1
export _CPPFLAGS="$CPPFLAGS -DNSPR_STATIC"
export _LDFLAGS="-Wl,--allow--multiple-definition"
# for gcc5
#export CPPFLAGS="$CPPFLAGS -fno-inline -I$IPATH/include/nspr"
export CPPFLAGS="$CPPFLAGS -I$IPATH/include/nspr"
cd $SPATH/nss-3.15.5
set +e
rm -rdf $SPATH/nss-3.15.5/dist
rm $IPATH/lib/libssl3.a $IPATH/lib/libnss3.a $IPATH/lib/libsoftokn3.a $IPATH/lib/libnssutil3.a $IPATH/lib/libsmime3.a
set -e
if [ "$MULTILIB" == "64" ]; then
export USE_64=1
fi
cp $IPATH/lib/libplds4_s.dll.a $IPATH/lib/libplds4.dll.a
cp $IPATH/lib/libplc4_s.dll.a $IPATH/lib/libplc4.dll.a
cp $IPATH/lib/libnspr4_s.dll.a $IPATH/lib/libnspr4.dll.a
cd nss
find . -name WIN954.0_gcc*.OBJ -exec rm -rdf {} +
set +e
make -k
set -e
if [ "$MULTILIB" == "64" ]; then
cd $SPATH/nss-3.15.5/dist/WIN954.0_gcc_64_OPT.OBJ/lib
else
cd $SPATH/nss-3.15.5/dist/WIN954.0_gcc_OPT.OBJ/lib
fi
rm *.dll.a libzlib.a 
rm $IPATH/lib/libnspr4.dll.a $IPATH/lib/libplc4.dll.a $IPATH/lib/libplds4.dll.a
mv libnss.a $IPATH/lib/libnss3.a
mv libsmime.a $IPATH/lib/libsmime3.a
mv libssl.a $IPATH/lib/libssl3.a
mv libsoftokn.a $IPATH/lib/libsoftokn3.a
for i in `find *.a`; do 
    ar x $i
    for j in `find *.o`; do
        mv $j ${i%.*}_${j%.*}.obj
    done
done
ar cru $IPATH/lib/libnssutil3.a *.obj
ranlib $IPATH/lib/libnssutil3.a
rm *.obj
cp -a $SPATH/nss-3.15.5/dist/public/nss $IPATH/include/
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include/nss
Name: NSS
Description: Network Security Services
Version: 3.15.5
Requires: nspr >= 4.8,zlib,sqlite3
Cflags: -I${includedir} -DNSS_STATIC -DNSS_USE_STATIC_LIBS
Libs: -L${libdir} -lsoftokn3 -lssl3 -lsmime3 -lnss3 -lnssutil3
' > $IPATH/lib/pkgconfig/nss.pc

cd $SPATH/libical-1.0
configure --disable-shared CPPFLAGS="$CPPFLAGS -DBIG_ENDIAN=0 -DLITTLE_ENDIAN=1 -DBYTE_ORDER=BIG_ENDIAN -I$IPATH/include/glib-2.0 -I$IPATH/lib/glib-2.0/include -DUSE_GLIB" LIBS=-lglib-2.0 --prefix=$IPATH
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libical-glib-1.0.2
set +e
rm $IPATH/lib/libical*.dll.a
set -e
configure --disable-static
make clean
make $PJOBS install
cp $IPATH/lib/libical-glib-1.0.dll.a $IPATH/lib/libicalvcal.dll.a
cp $IPATH/lib/libical-glib-1.0.dll.a $IPATH/lib/libical.dll.a
cp $IPATH/lib/libical-glib-1.0.dll.a $IPATH/lib/libicalss.dll.a

cd $SPATH/protobuf-2.4.1
configure --disable-shared --enable-static
make clean
make $PJOBS
make install
rm $IPATH/lib/*.la

cd $SPATH/libphonenumber/cpp
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel
make clean
make $PJOBS install
cp src/phonenumbers/base/*.h $IPATH/include/phonenumbers/base/
cp src/phonenumbers/base/memory/*.h $IPATH/include/phonenumbers/base/memory/

cd $SPATH/evolution-data-server-3.18.1
configure --with-openldap --disable-uoa --with-krb5 --with-krb5-includes=$IPATH/include/heimdal --with-krb5-libs=$IPATH/lib $INTROSPECT LIBS="-lsasl2 -lssl -lws2_32 -lwldap32"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/yajl-2.1.0
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel
make clean
make $PJOBS install
rm $IPATH/lib/libyajl.dll.a
mv $IPATH/lib/libyajl_s.a $IPATH/lib/libyajl.a

cd $SPATH/portablexdr-4.9.1
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la
#needed to resolve declspec in libguestfs
echo '
#include <winsock2.h>
' >> $IPATH/include/rpc/rpc.h

cd $SPATH/file-5.14
configure --enable-static --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/hivex-1.3.10
configure --disable-ruby --disable-ocaml --disable-python --disable-perl --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libguestfs-1.22.9
configure --enable-threads=windows --disable-static --disable-daemon --disable-appliance --disable-lua --disable-ruby --disable-python --disable-erlang --disable-perl --disable-ocaml --disable-haskell --disable-php --without-libvirt $INTROSPECT LIBS=-lregex
set +e
rm $IPATH/lib/libguestfs*
rm -rdf $IPATH/include/guestfs*
set -e
make clean
cd gnulib/lib
make $PJOBS
cd ../../src
make $PJOBS install
cd ../gobject
echo "./guestfs-scan.tmp.exe" > docs/guestfs-scan.tmp
make -j2
make install
rm $IPATH/lib/*.la

cd $SPATH/libvirt-0.10.2
# additional cppflags needed when sasl enabled, to override gnulib iovec
configure --without-python --without-phyp --without-lxc --without-openvz --without-libvirtd --disable-static CPPFLAGS="$CPPFLAGS -DGNULIB_defined_struct_iovec=1"
make clean
make $PJOBS
manifest
make install
rm $IPATH/lib/*.la

cd $SPATH/libvirt-glib-0.2.2
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/folks-0.10.1
# gir missing shared-library
configure --disable-vala --disable-eds-backend --disable-static --disable-tests
find . -name *.lo -exec rm {} +
find . -name *.exe -exec rm {} +
find . -name *.o -exec rm {} +
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libmirage-3.0.3
set +e
rm $IPATH/lib/libmirage.*
set -e
export PATH=$SPATH/libmirage-3.0.3:$PATH
# gir missing shared-library
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
if [ "$CROSSX" == "1" ]; then
cmake -G "MSYS Makefiles" -DGTKDOC_ENABLED=OFF -DINTROSPECTION_ENABLED=OFF -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS"
else
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS"
fi
make clean
make install
cp libmirage.dll $IPATH/bin/
export PATH=$(echo $PATH | sed -e "s;$SPATH/libmirage-3\.0\.3:;;")

cd $SPATH/midgard2-core-12.09
configure --with-libgda5 --with-dbus-support $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/glib-controller
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: uuid
Description: win32 uuid
Version: 1.50
Requires: 
Cflags: 
Libs: -lrpcrt4
' > $IPATH/lib/pkgconfig/uuid.pc
cd $SPATH/couchdb-glib-0.7.4
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgami-0.3
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gocl-0.2.0
if [ "$MULTILIB" == "64" ]; then
echo '
LIBRARY "OpenCL.dll"
EXPORTS
clBuildProgram
clCompileProgram
clCreateBuffer
clCreateCommandQueue
clCreateContext
clCreateContextFromType
clCreateFromGLBuffer
clCreateFromGLRenderbuffer
clCreateFromGLTexture2D
clCreateFromGLTexture3D
clCreateFromGLTexture
clCreateImage2D
clCreateImage3D
clCreateImage
clCreateKernel
clCreateKernelsInProgram
clCreateProgramWithBinary
clCreateProgramWithBuiltInKernels
clCreateProgramWithSource
clCreateSampler
clCreateSubBuffer
clCreateSubDevices
clCreateUserEvent
clEnqueueAcquireGLObjects
clEnqueueBarrier
clEnqueueBarrierWithWaitList
clEnqueueCopyBuffer
clEnqueueCopyBufferRect
clEnqueueCopyBufferToImage
clEnqueueCopyImage
clEnqueueCopyImageToBuffer
clEnqueueFillBuffer
clEnqueueFillImage
clEnqueueMapBuffer
clEnqueueMapImage
clEnqueueMarker
clEnqueueMarkerWithWaitList
clEnqueueMigrateMemObjects
clEnqueueNDRangeKernel
clEnqueueNativeKernel
clEnqueueReadBuffer
clEnqueueReadBufferRect
clEnqueueReadImage
clEnqueueReleaseGLObjects
clEnqueueTask
clEnqueueUnmapMemObject
clEnqueueWaitForEvents
clEnqueueWriteBuffer
clEnqueueWriteBufferRect
clEnqueueWriteImage
clFinish
clFlush
clGetCommandQueueInfo
clGetContextInfo
clGetDeviceIDs
clGetDeviceInfo
clGetEventInfo
clGetEventProfilingInfo
clGetExtensionFunctionAddress
clGetExtensionFunctionAddressForPlatform
clGetGLObjectInfo
clGetGLTextureInfo
clGetImageInfo
clGetKernelArgInfo
clGetKernelInfo
clGetKernelWorkGroupInfo
clGetMemObjectInfo
clGetPlatformIDs
clGetPlatformInfo
clGetProgramBuildInfo
clGetProgramInfo
clGetSamplerInfo
clGetSupportedImageFormats
clLinkProgram
clReleaseCommandQueue
clReleaseContext
clReleaseDevice
clReleaseEvent
clReleaseKernel
clReleaseMemObject
clReleaseProgram
clReleaseSampler
clRetainCommandQueue
clRetainContext
clRetainDevice
clRetainEvent
clRetainKernel
clRetainMemObject
clRetainProgram
clRetainSampler
clSetCommandQueueProperty
clSetEventCallback
clSetKernelArg
clSetMemObjectDestructorCallback
clSetUserEventStatus
clUnloadCompiler
clUnloadPlatformCompiler
clWaitForEvents
' > $IPATH/lib/OpenCl.def
dlltool --as-flags=--64 -m i386:x86-64 -l $IPATH/lib/libopencl.a -d $IPATH/lib/OpenCL.def
else
echo '
LIBRARY "OpenCL.dll"
EXPORTS
clBuildProgram@24
clCompileProgram@36
clCreateBuffer@24
clCreateCommandQueue@20
clCreateContext@24
clCreateContextFromType@24
clCreateFromGLBuffer@20
clCreateFromGLRenderbuffer@20
clCreateFromGLTexture2D@28
clCreateFromGLTexture3D@28
clCreateFromGLTexture@28
clCreateImage2D
clCreateImage3D
clCreateImage@28
clCreateKernel@12
clCreateKernelsInProgram@16
clCreateProgramWithBinary@28
clCreateProgramWithBuiltInKernels@20
clCreateProgramWithSource@20
clCreateSampler@20
clCreateSubBuffer@24
clCreateSubDevices@20
clCreateUserEvent@8
clEnqueueAcquireGLObjects@24
clEnqueueBarrier@4
clEnqueueBarrierWithWaitList@16
clEnqueueCopyBuffer@36
clEnqueueCopyBufferRect@52
clEnqueueCopyBufferToImage@36
clEnqueueCopyImage@36
clEnqueueCopyImageToBuffer@36
clEnqueueFillBuffer@36
clEnqueueFillImage@32
clEnqueueMapBuffer@44
clEnqueueMapImage@52
clEnqueueMarker@8
clEnqueueMarkerWithWaitList@16
clEnqueueMigrateMemObjects@32
clEnqueueNDRangeKernel@36
clEnqueueNativeKernel@40
clEnqueueReadBuffer@36
clEnqueueReadBufferRect@56
clEnqueueReadImage@44
clEnqueueReleaseGLObjects@24
clEnqueueTask@20
clEnqueueUnmapMemObject@24
clEnqueueWaitForEvents@12
clEnqueueWriteBuffer@36
clEnqueueWriteBufferRect@56
clEnqueueWriteImage@44
clFinish@4
clFlush@4
clGetCommandQueueInfo@20
clGetContextInfo@20
clGetDeviceIDs@24
clGetDeviceInfo@20
clGetEventInfo@20
clGetEventProfilingInfo@20
clGetExtensionFunctionAddress@4
clGetExtensionFunctionAddressForPlatform@8
clGetGLObjectInfo@12
clGetGLTextureInfo@20
clGetImageInfo@20
clGetKernelArgInfo@24
clGetKernelInfo@20
clGetKernelWorkGroupInfo@24
clGetMemObjectInfo@20
clGetPlatformIDs@12
clGetPlatformInfo@20
clGetProgramBuildInfo@24
clGetProgramInfo@20
clGetSamplerInfo@20
clGetSupportedImageFormats@28
clLinkProgram@36
clReleaseCommandQueue@4
clReleaseContext@4
clReleaseDevice@4
clReleaseEvent@4
clReleaseKernel@4
clReleaseMemObject@4
clReleaseProgram@4
clReleaseSampler@4
clRetainCommandQueue@4
clRetainContext@4
clRetainDevice@4
clRetainEvent@4
clRetainKernel@4
clRetainMemObject@4
clRetainProgram@4
clRetainSampler@4
clSetCommandQueueProperty@20
clSetEventCallback@16
clSetKernelArg@16
clSetMemObjectDestructorCallback@12
clSetUserEventStatus@8
clUnloadCompiler
clUnloadPlatformCompiler@4
clWaitForEvents@8
' > $IPATH/lib/OpenCl.def
dlltool -k -A -l $IPATH/lib/libopencl.a -d $IPATH/lib/OpenCL.def
fi
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: OpenCL
Description: Open Computing Language generic Installable Client Driver Loader
Version: 1.2.1
Libs: -lOpenCL
Cflags: 
' > $IPATH/lib/pkgconfig/OpenCL.pc
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la
cp gocl/Gocl-0.2.gir $IPATH/share/gir-1.0/

cd $SPATH/liblangtag-0.5.6
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libunistring-0.9.4
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/mongo-glib-0.3.2
configure --disable-static $INTROSPECT --disable-debug CPPFLAGS="$CPPFLAGS -D__GLIBC__=4 -DCONFIG_UNICODE_SAFETY=1" LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/sqlheavy-master
# gir need recompile
configure --disable-static --disable-valadoc $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gcab-0.6
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgovirt-0.3.3
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libitl-0.7.0
$CC $CFLAGS -c -Iprayertime/src -Ihijri/src prayertime/src/astro.c prayertime/src/prayer.c  hijri/src/umm_alqura.c hijri/src/hijri.c
ar cru $IPATH/lib/libitl.a *.o
ranlib $IPATH/lib/libitl.a
if [ ! -d $IPATH/include/itl ]; then
mkdir $IPATH/include/itl
fi
cp prayertime/src/prayer.h hijri/src/hijri.h $IPATH/include/itl/

cd $SPATH/libitl-gobject-0.2.1
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gavl-1.2.0
configure --disable-shared --enable-static --without-doxygen --disable-cpu-clip --with-cpuflags=none
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/frei0r-plugins-1.4
configure
make clean
make $PJOBS install
# cause error during gst-inspect
rm $IPATH/lib/frei0r-1/rgbparade.dll
# this one pretty much silly fx
rm $IPATH/lib/frei0r-1/vectorscope.dll
rm $IPATH/lib/frei0r-1/test*.dll
# dupe of gstopencv
rm $IPATH/lib/frei0r-1/facebl0r.dll
rm $IPATH/lib/frei0r-1/facedetect.dll
#crashed
#rm $IPATH/lib/frei0r-1/partik0l.dll

cd $SPATH/libvisual-plugins-0.4.0
#corona error with c++11
#configure --disable-gforce --disable-corona --disable-nls --disable-static CFLAGS="$CFLAGS -O2"
mv $IPATH/lib/libstdc++.dll.a $IPATH/lib/libstdc++_s.a
configure --disable-gforce --disable-nls --disable-static CFLAGS="$CFLAGS -O2"
make clean
make $PJOBS install
cd plugins/input/jack
make clean
make $PJOBS install
mv $IPATH/lib/libstdc++_s.a $IPATH/lib/libstdc++.dll.a

cd $SPATH/lunar-date-2.4.0 
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/lunar-calendar-3.0.0
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/desktop-file-utils-0.22
configure
make clean
make install

cd $SPATH/gnome-dictionary-3.18.0
configure LIBS=-lws2_32 CPPFLAGS="$CPPFLAGS -DENABLE_IPV6"
make clean
make $PJOBS
make install
rm $IPATH/lib/*.la

cd $SPATH/gdb-7.8
if [ "$2" == "90" ]; then
list="27 31 32"
else
list="33 34"
fi
for i in $list; do
set +e
make distclean
find . -name config.cache -exec rm {} +
set -e
configure --disable-nls --with-64-bit-bfd --with-zlib --with-pkgversion=tumaG86 --disable-werror --with-python=/usr/bin/python$i$MULTILIB --prefix=$IPATH/py$i
make $PJOBS
make install
mv $IPATH/py$i/bin/gdb.exe $IPATH/py$i/bin/gdb-py$i.exe 
mv $IPATH/py$i/bin/gdbserver.exe $IPATH/py$i/bin/gdbserver-py$i.exe 
done

cd $SPATH/gucharmap-3.18.0
configure $INTROSPECT
make clean
make
manifest
make install
cd docs
make install
rm $IPATH/lib/*.la

cd $SPATH/gtranslator-2.91.7
configure LIBS=-lintl $INTROSPECT
make clean
make
manifest
make install
cd doc
make install
rm $IPATH/lib/*.la

# to be replaced with gnome builder
cd $SPATH/gedit-3.18.2
if [ -f gedit/gedit-res.o ]; then rm gedit/gedit-res.o; fi
if [ "$2" == "90" ]; then
configure --disable-user-help --disable-updater --disable-maintainer-mode --enable-compile-warnings=minimum --disable-introspection
else
configure  --enable-python --disable-user-help --disable-updater --disable-maintainer-mode --enable-compile-warnings=minimum $INTROSPECT PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$IPATH/py34/lib/pkgconfig" PYTHON=/usr/bin/python34
fi
make clean
make $PJOBS
manifest
make install

cd $SPATH/gedit-plugins-3.18.0
if [ "$2" == "90" ]; then
configure
else
configure  --enable-python PYTHON=/usr/bin/python34 PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$IPATH/py34/lib/pkgconfig"
fi
make clean
make $PJOBS
make install

cd $SPATH/gedit-code-assistance-3.16.0
configure --disable-static
find . -name *.lo -exec rm {} +
make install

cd $SPATH/ghex-3.18.0
configure --enable-compile-warnings=minimum
make clean
make 
make install
rm $IPATH/lib/*.la
#postw32 -m gui -i $IPATH/bin/ghex.exe

cd $SPATH/msitools-0.94
configure --disable-static $INTROSPECT
set +e
find . -name *.lo -exec rm {} +
find . -name *.o -exec rm {} +
set -e
make $PJOBS install
rm $IPATH/lib/*.la

if [ ! -d $IPATH/lib/ladspa ]; then mkdir $IPATH/lib/ladspa; fi

mv $IPATH/lib/libstdc++.dll.a $IPATH/lib/libstdc++_s.a
cd $SPATH/ladspa_sdk/cmt
cd src
make clean
make $PJOBS 
cp ../plugins/cmt.dll $IPATH/lib/ladspa/
cd $SPATH/ladspa_sdk/caps-0.9.24
make clean
make $PJOBS 
cp *.dll $IPATH/lib/ladspa/
cd $SPATH/ladspa_sdk/VCO-plugins-0.3.0
make clean 
make $PJOBS 
cp *.dll $IPATH/lib/ladspa/
cd $SPATH/ladspa_sdk/REV-plugins-0.3.1
make clean 
make $PJOBS 
cp *.dll $IPATH/lib/ladspa/
cd $SPATH/ladspa_sdk/AMB-plugins-0.1.0
make clean 
make $PJOBS
cp *.dll $IPATH/lib/ladspa/
cd $SPATH/ladspa_sdk/MCP-plugins-0.3.0
make clean
make $PJOBS 
cp *.dll $IPATH/lib/ladspa/
cd $SPATH/ladspa_sdk/LEET-plugins-0.2
make clean
make $PJOBS  all
cp *.dll $IPATH/lib/ladspa/
cd $SPATH/ladspa_sdk/aweight
make clean 
make $PJOBS awplug.dll
cp *.dll $IPATH/lib/ladspa/
cd $SPATH/ladspa_sdk/blepvco-0.1.0
make clean 
make $PJOBS
cp *.dll $IPATH/lib/ladspa/
cd $SPATH/ladspa_sdk/vocoder-0.3
make clean 
make $PJOBS 
cp *.dll $IPATH/lib/ladspa/
cd $SPATH/ladspa_sdk/pvoc-0.1.12
make clean 
make $PJOBS 
cp *.dll $IPATH/lib/ladspa/
mv $IPATH/lib/libstdc++_s.a $IPATH/lib/libstdc++.dll.a

#begin c++
cd $SPATH/ladspa_sdk/vlevel-0.5
make clean 
make $PJOBS 
cp *.dll $IPATH/lib/ladspa/vlevel.dll

cd $SPATH/ladspa_sdk/guitarix-0.28.2/ladspa
$CXX $CXXFLAGS -shared -o guitarix_crybaby.dll crybaby.cpp $LDFLAGS
$CXX $CXXFLAGS -shared -o guitarix_distortion.dll distortion.cpp $LDFLAGS
$CXX $CXXFLAGS -shared -o guitarix_echo.dll echo.cpp $LDFLAGS
$CXX $CXXFLAGS -shared -o guitarix_freeverb.dll freeverb.cpp $LDFLAGS
$CXX $CXXFLAGS -shared -o guitarix.dll guitarix-ladspa.cpp $LDFLAGS
$CXX $CXXFLAGS -shared -o guitarix_compressor.dll monocompressor.cpp $LDFLAGS
$CXX $CXXFLAGS -shared -o guitarix_amp.dll monoamp.cpp $LDFLAGS
$CXX $CXXFLAGS -shared -o guitarix_IR.dll impulseresponse.cpp $LDFLAGS
cp *.dll $IPATH/lib/ladspa/

cd $SPATH/ladspa_sdk/calf-master
configure --without-lv2 --without-lash --enable-sse --without-dssi LIBS=-lws2_32
make clean
if [ "$MULTILIB" == "64" ]; then 
set +e
make $PJOBS install -k
set -e
else
make $PJOBS install
fi

cd $SPATH/ladspa_sdk/lemux-0.2
make clean
cd $SPATH/ladspa_sdk/lemux-0.2/dev/SID/resid
configure
make clean
make $PJOBS 
cd $SPATH/ladspa_sdk/lemux-0.2
make $PJOBS
cp gen/*.dll $IPATH/lib/ladspa/

cd $SPATH/ladspa_sdk/vamp-plugin-sdk-2.5
configure --disable-shared
make clean 
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/ladspa_sdk/rubberband-1.7.0
configure
make clean 
make $PJOBS install
rm $IPATH/lib/ladspa/*.cat

cd $SPATH/ladspa_sdk/faust-2.0.a30
cd examples
rm ladspadir/*.dll
if [ ! -d $SPATH/ladspa_sdk/faust-2.0.a30/examples/ladspadir ]; then mkdir $SPATH/ladspa_sdk/faust-2.0.a30/examples/ladspadir; fi
export FAUST_LIB_PATH=/opt/lib/faust
make -f Makefile.ladspacompile V=1 $PJOBS
rm ladspadir/*ester.dll
cp ladspadir/*.dll $IPATH/lib/ladspa
unset FAUST_LIB_PATH
#endf C++

cd $SPATH/ladspa_sdk/blop-0.2.8
configure --disable-nls LIBS=-ldl
make clean
make
if [ ! -d $IPATH/lib/ladspa/blop_files ]; then mkdir $IPATH/lib/ladspa/blop_files; fi
cp src/*.dll $IPATH/lib/ladspa/
mv $IPATH/lib/ladspa/*data.dll $IPATH/lib/ladspa/blop_files/

cd $SPATH/ladspa_sdk/csa-0.5.100810
configure --disable-nls
make clean
make $PJOBS install
rm $IPATH/lib/ladspa/*.a $IPATH/lib/ladspa/*.la

cd $SPATH/ladspa_sdk/invada-studio-plugins-0.3.1
make clean
make $PJOBS 
cp *.dll $IPATH/lib/ladspa/

cd $SPATH/ladspa_sdk/omins-0.2.0
configure
make clean 
make $PJOBS install

cd $SPATH/ladspa_sdk/vcf-0.0.5
set +e
rm *.o *.dll
set -e
make $PJOBS
cp *.dll $IPATH/lib/ladspa/

cd $SPATH/ladspa_sdk/njl-plugins
set +e
rm *.o *.dll
set -e
make $PJOBS
cp *.dll $IPATH/lib/ladspa/

cd $SPATH/ladspa_sdk/tap-plugins-0.7.1
make clean 
make $PJOBS 
cp *.dll $IPATH/lib/ladspa/

cd $SPATH/ladspa_sdk/wasp-0.1.4
make clean 
make $PJOBS 
cp plugins/*.dll $IPATH/lib/ladspa/

cd $SPATH/isas-isas
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
cd docs
make install
rm $IPATH/lib/*.la

cd $SPATH/kpathsea
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/evince-3.18.1
mv $IPATH/lib/libstdc++.dll.a $IPATH/lib/libstdc++_s.a
configure --disable-thumbnailer --disable-static --disable-browser-plugin --disable-nautilus --disable-libgnome-desktop --with-platform=win32 $INTROSPECT LIBS="-ljpeg -lstdc++"
make clean
make
manifest
if [ "$CROSSX" == "1" ]; then
set +e
make $PJOBS install -k
set -e
else
make $PJOBS install
fi
rm $IPATH/lib/*.la
mv $IPATH/lib/libstdc++_s.a $IPATH/lib/libstdc++.dll.a

cd $SPATH/libisocodes-1.0
# gir missing shared-library
configure --disable-static
find . -name *.lo -exec rm {} +
find . -name *.exe -exec rm {} +
find . -name *.o -exec rm {} +
echo "">libisocodes_la_vala.stamp
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/jansson-2.6
configure --disable-shared --enable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libskk-1.0.2
#gir fix shared-library
configure --disable-static --disable-docs $INTROSPECT
find . -name *.la -exec rm {} +
find . -name *.lo -exec rm {} +
find . -name *.gir -exec rm {} +
find . -name *.typelib -exec rm {} +
cd libskk
set +e
make -j2
patch -p1 -i ../util.patch
make
make install-libLTLIBRARIES
make install-typelibDATA
make install-girDATA
make install-libskkincludeHEADERS
make install-pkgconfigDATA
cd ..
make -j2
cd tools
make install
cd ../docs
make install
cd ../rules
make install
set -e
rm $IPATH/lib/*.la

cd $SPATH/dee-1.2.7
configure --disable-tests $INTROSPECT LIBS=-licuuc
make clean
make $PJOBS install
cd doc/reference/dee-1.0
make install
rm $IPATH/lib/*.la

cd $SPATH/totem-pl-parser-3.10.5
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/grilo-0.2.15
configure --disable-static --disable-vala $INTROSPECT
make clean
make $PJOBS install
cd doc/grilo
make install
rm $IPATH/lib/*.la

#patch makefile.in exclude vala subdir
cd $SPATH/gupnp-av-0.12.7
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gupnp-dlna-0.10.2
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#cd $SPATH/gupnp-tools-0.8.9
#configure --disable-static $INTROSPECT
#make clean
#make $PJOBS install

cd $SPATH/libdmapsharing-2.9.32
configure --disable-static --with-mdns=dns_sd LIBS="-ldns_sd -lws2_32"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gom-0.3.0
configure --enable-debug=minimum --disable-static $INTROSPECT LIBS=-lintl
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/grilo-plugins-0.2.16
configure --disable-static --enable-compile-warnings=minimum
make clean
make $PJOBS install

cd $SPATH/libunique-3.0.2
if [ -f unique/dbus/uniquebackend-glue.h ]; then rm -rdf unique/dbus/uniquebackend-glue.h ; fi
if [ -f unique/dbus/uniquebackend-bindings.h ]; then rm -rdf unique/dbus/uniquebackend-bindings.h ; fi
configure --enable-dbus --disable-bacon $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/catch-glib-master
configure --enable-debug=minimum $INTROSPECT LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libwaveform-master
set +e
configure --disable-static $INTROSPECT
make clean
make $PJOBS install-exec
make install-libwaveformdocDATA
make install -k
set -e
rm $IPATH/lib/*.la

cd $SPATH/libappnet-0.0.4
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gfbgraph-0.2.2
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#c++
cd $SPATH/libtorrent-rasterbar-1.0.6
configure --disable-shared --enable-static --with-boost-system=boost_system CXXFLAGS="$CXXFLAGS -DTORRENT_USE_WSTRING -D_UNICODE -DUNICODE -DTORRENT_BUILDING_SHARED -DBOOST_ASIO_SOURCE"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/torrent-glib
# wsock32 needed by ASIO inlines
configure --disable-static --enable-shared CXXFLAGS="$CXXFLAGS -DBOOST_ASIO_SOURCE" LIBS="-lcrypto -lssl -lws2_32 -lwsock32"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libsexy3
configure --disable-static --disable-vala $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la
XXX
cd $SPATH/gspell-0.2.1
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la
:<<"XXX"
#c++
cd $SPATH/GtkScintilla-master
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/mash-0.2.0
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/cattle-1.2.0
configure --disable-static $INTROSPECT CFLAGS="$CFLAGS -O2"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/iris-master
# gir need recompile
configure --disable-static --disable-maintainer-flags --enable-debug=minimum $INTROSPECT
make clean
make install
rm $IPATH/lib/*.la

cd $SPATH/libfreenect-0.4.1
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel -DTHREADS_PTHREADS_INCLUDE_DIR=$IPATH/include -DTHREADS_PTHREADS_WIN32_LIBRARY=$IPATH/lib/libpthread.dll.a -DBUILD_EXAMPLES=OFF #-DBUILD_AUDIO=ON
make clean
make $PJOBS
make install
rm $IPATH/lib/libfreenect*dll.*
echo 'prefix=
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include/libfreenect
Name: libfreenect
Description: Interface to the Microsoft Kinect sensor device.
Requires: libusb-1.0
Version: 0.4
Libs: -L${libdir} -lfreenect
Cflags: -I${includedir}
' > $IPATH/lib/pkgconfig/libfreenect.pc

cd $SPATH/GFreenect-master
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libtranslit-0.0.3
configure --disable-static --disable-m17n-lib --enable-icu $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#c++
cd $SPATH/zeromq-3.2.4
configure --enable-static --disable-shared CPPFLAGS="$CPPFLAGS -DZMQ_STATIC"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/ufo-core-0.8.0
configure --disable-static $INTROSPECT CPPFLAGS="$CPPFLAGS -DZMQ_STATIC" CFLAGS="$CFLAGS -O2"
make clean
make install
rm $IPATH/lib/*.la

cd $SPATH/swe-glib-1.0.1
configure --disable-static --disable-nls $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/megatools-1.9.93
configure --disable-static --disable-docs-build $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/bayes-glib-master
configure --disable-static --enable-debug=minimum --disable-maintainer-mode $INTROSPECT LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/aws-glib-master
configure --disable-static --enable-debug=minimum --disable-maintainer-mode $INTROSPECT LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/push-glib-master
configure --disable-static --enable-debug=minimum --disable-maintainer-mode $INTROSPECT LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/oclfft-1.2.0
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DOPENCL_LIBRARIES=$IPATH/lib/libopencl.a -DOPENCL_INCLUDE_DIRS=$IPATH/include
make clean
make $PJOBS install
cp src/*.dll $IPATH/bin/
cp src/*.a $IPATH/lib/

cd $SPATH/ufo-art/core
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DOPENCL_LIBRARIES=$IPATH/lib/libopencl.a -DOPENCL_INCLUDE_DIRS=$IPATH/include
make clean
make $PJOBS install
cp ufo/*.dll $IPATH/bin/
cp ufo/*.a $IPATH/lib/

cd $SPATH/ufo-art/plugins
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DOPENCL_LIBRARIES=$IPATH/lib/libopencl.a -DOPENCL_INCLUDE_DIRS=$IPATH/include
make clean
make $PJOBS install
cp build/*.dll $IPATH/lib/ufo/

cd $SPATH/libhdate-1.6.02
configure --disable-shared --disable-perl --disable-gpc --disable-ruby --disable-fpc --disable-python --disable-php --disable-hcal CPPFLAGS="$CPPFLAGS $(pkg-config --cflags glib-2.0)"
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libhdate-glib-0.5.0
configure $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/telepathy-ring-2.2.2
configure --disable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gplugin-pkg-upstream-0.0.20
if [ "$2" == "90" ]; then
list="31 32"
else
list="33 34"
fi
for i in $list; do
if [ -f CMakeCache.txt ]; then rm -rdf CMakeFiles/ CMakeCache.txt; fi
cmake -G "MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$IPATH -DCMAKE_BUILD_TYPE=MinSizeRel -DPYTHON3_INCLUDE_DIRS=/c/python$i/include -DPYGOBJECT_INCLUDE_DIRS=$IPATH/py$i/include/pygobject-3.0 -DPYTHON3_LIBRARIES=$IPATH/lib/libpython$i.dll.a
make clean
make $PJOBS install
mv $IPATH/lib/gplugin/gplugin-python.dll $IPATH/lib/gplugin/gplugin-python$i.dll
mv $IPATH/lib/libgplugin*.dll $IPATH/bin
done

cd $SPATH/pidgin3
configure --disable-nss --disable-avahi --disable-nm --disable-consoleui --disable-gtkui --without-x --with-win32-dirs=fhs --enable-cyrus-sasl $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/model
configure --disable-static
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libcereal-master
# gir missing shared-library
configure
find . -name *.lo -exec rm {} +
find . -name *.exe -exec rm {} +
find . -name *.o -exec rm {} +
echo "">cereal/libcereal_la_vala.stamp
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/log4g-0.1.2
configure $INTROSPECT LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/msgpack-c-cpp-0.5.8
configure --disable-shared --disable-cxx
make clean
make $PJOBS install
rm $IPATH/lib/*.la

#c++
cd $SPATH/kytea-0.4.6
configure --disable-shared
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/groonga-4.0.8
mv $IPATH/lib/libstdc++.dll.a $IPATH/lib/libstdc++_s.a
configure --disable-groonga-httpd --disable-document --with-zlib --disable-static --disable-benchmark LIBS=-lws2_32
make clean
cd vendor/onigmo-source
make $PJOBS
cd ../../
make install
rm $IPATH/lib/*.la
mv $IPATH/lib/libstdc++_s.a $IPATH/lib/libstdc++.dll.a

cd $SPATH/groonga-gobject-1.0.1
configure --disable-static
make clean
if [ "$CROSSX" == "1" ]; then
make install-pkgconfigDATA
cd groonga-gobject
make install-libLTLIBRARIES
else
make $PJOBS install
fi
rm $IPATH/lib/*.la

if [ "$2" == "90" ]; then
cd $SPATH/gtkparasite-master
configure --disable-static PYTHON=python27$MULTILIB PYGTK_CFLAGS=-I$IPATH/py27/include/pygobject-3.0 PYGTK_LIBS=-lpython27 PYTHON_CONFIG=/bin/python27-config LIBS=-ldl
make clean
make $PJOBS install
fi

cd $SPATH/Skeltrack-0.1.14
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/json-rpc-glib-master
configure --disable-static $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gob_2_0_19
configure
make clean
make $PJOBS install

cd $SPATH/libosinfo-0.2.12
configure --disable-static --disable-tests $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/gnome-autoar-master
configure --disable-static $INTROSPECT
make clean
make install
rm $IPATH/lib/*.la

cd $SPATH/libfso-glib-2012.07.27.2
# gir missing shared-library
configure --enable-typelib
find . -name *.lo -exec rm {} +
find . -name *.exe -exec rm {} +
find . -name *.o -exec rm {} +
echo "">src/libfso_glib_la_vala.stamp
make install
rm $IPATH/lib/*.la

cd $SPATH/hiredis-win32-master
make clean
make PREFIX=$IPATH install

cd $SPATH/redis-glib-master
configure --enable-debug=minimum --disable-static LIBS=-lws2_32
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libntlm-1.4
configure --disable-shared --enable-static
make clean 
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libgsasl-1.6.1
configure --disable-shared --enable-static --enable-kerberos_v5 --with-gssapi-impl=heimdal CPPFLAGS="$CPPFLAGS -I$IPATH/include/heimdal" LIBS=-lntlm
make clean 
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/libinfinity-master
source setgcc gcc5
configure --disable-static $INTROSPECT LIBS="-lgssapi32 -lgcrypt -lidn -lntlm"
make clean 
make install
rm $IPATH/lib/*.la
source setgcc gcc48

cd $SPATH/libmediaart-0.3.0
configure --disable-unit-tests $INTROSPECT
make clean
make $PJOBS install
rm $IPATH/lib/*.la

cd $SPATH/aravis-0.3.6
configure  --enable-gst-plugin --disable-static --enable-viewer $INTROSPECT LIBS=-lws2_32
make clean
if [ "$CROSSX" == "1" ]; then
set +e
make $PJOBS install -k
set -e
else
make $PJOBS install
fi
rm $IPATH/lib/*.la
mv $IPATH/lib/gstreamer-1.0/libgstaravis-0.4.dll $IPATH/lib/gstreamer-1.0/libgstaravis.dll

cd $SPATH/ctags-deploy
configure LIBS=-lregex --disable-external-sort
make clean
make $PJOBS install

cd $SPATH/pinpoint-0.1.8
configure
make clean
make $PJOBS install

cd $SPATH/gtkhtml-4.10.0
configure --enable-static --disable-shared
make clean
make $PJOBS install
:<<"XXXX"
cd $SPATH/gnome-devel-docs-3.18.0
find . -name *.html -exec rm {} +
find . -name *.css -exec rm {} +
find . -name *.cache -exec rm {} +
cd $SPATH/gnome-devel-docs-3.18.0/programming-guidelines/C
yelp-build html *.page
cd $SPATH/gnome-devel-docs-3.18.0/platform-overview/C
yelp-build html *.page
cd $SPATH/gnome-devel-docs-3.18.0/platform-demos/C
yelp-build html *.page
cd $SPATH/gnome-devel-docs-3.18.0/optimization-guide/C
yelp-build html *.page
cd $SPATH/gnome-devel-docs-3.18.0/hig/C
yelp-build html *.page
cd $SPATH/gnome-devel-docs-3.18.0/accessibility-devel-guide/C
db2html index.docbook

cd $SPATH/mypaint-git
if [ "$2" == "90" ]; then
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$IPATH/py27/lib/pkgconfig"
else
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$IPATH/py34/lib/pkgconfig"
fi
/c/python27/scripts/scons -c 
set +e
/c/python27/scripts/scons enable_introspection=1
set -e
$CC $LDFLAGS $CXXFLAGS -fopenmp -shared -o libmypaint.dll brushlib/brushmodes.o brushlib/fifo.o brushlib/helpers.o brushlib/mapping.o brushlib/mypaint-brush-settings.o brushlib/mypaint-brush.o brushlib/mypaint-fixed-tiled-surface.o brushlib/mypaint-rectangle.o brushlib/mypaint-surface.o brushlib/mypaint-tiled-surface.o brushlib/mypaint.o brushlib/operationqueue.o brushlib/rng-double.o brushlib/tilemap.o brushlib/utils.o -L$IPATH/lib -lm -ljson-c -lgobject-2.0 -lglib-2.0 -lintl -Wl,--out-implib,brushlib/libmypaint.a

g-ir-scanner -o brushlib/MyPaint-1.1.gir --warn-all --namespace=MyPaint --nsversion=1.1 -I./brushlib -L./brushlib --add-include-path=./ --identifier-prefix=MyPaint --symbol-prefix=mypaint_ --pkg=glib-2.0 -I./ --library=mypaint brushlib/brushmodes.c brushlib/fifo.c brushlib/helpers.c brushlib/libmypaint.c brushlib/mapping.c brushlib/mypaint-brush-settings.c brushlib/mypaint-brush.c brushlib/mypaint-fixed-tiled-surface.c brushlib/mypaint-rectangle.c brushlib/mypaint-surface.c brushlib/mypaint-tiled-surface.c brushlib/mypaint.c brushlib/operationqueue.c brushlib/rng-double.c brushlib/tilemap.c brushlib/utils.c brushlib/mypaint-brush-settings-gen.h brushlib/mypaint-brush-settings.h brushlib/mypaint-brush.h brushlib/mypaint-config.h brushlib/mypaint-fixed-tiled-surface.h brushlib/mypaint-glib-compat.h brushlib/mypaint-rectangle.h brushlib/mypaint-surface.h brushlib/mypaint-tiled-surface.h brushlib/glib/mypaint-brush.c brushlib/glib/mypaint-brush.h

g-ir-compiler -o $IPATH/lib/girepository-1.0/MyPaint-1.1.typelib brushlib/MyPaint-1.1.gir 
cp brushlib/MyPaint-1.1.gir $IPATH/share/gir-1.0
rm brushlib/libmypaint.a
cp libmypaint.dll $IPATH/bin
XXXX

# empty shared-library
sed --in-place -e "s;shared-library=\"\";shared-library=\"libgobject-2.0-0.dll\";" $IPATH/share/gir-1.0/GObject-2.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/GObject-2.0.typelib $IPATH/share/gir-1.0/GObject-2.0.gir
sed --in-place -e "s;shared-library=\"\";shared-library=\"libgio-2.0-0.dll\";" $IPATH/share/gir-1.0/Gio-2.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Gio-2.0.typelib $IPATH/share/gir-1.0/Gio-2.0.gir
sed --in-place -e "s;shared-library=\"\";shared-library=\"libgmodule-2.0-0.dll\";" $IPATH/share/gir-1.0/GModule-2.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/GModule-2.0.typelib $IPATH/share/gir-1.0/GModule-2.0.gir
sed --in-place -e "s;shared-library=\"\";shared-library=\"libglib-2.0-0.dll,libgobject-2.0-0.dll\";" $IPATH/share/gir-1.0/GLib-2.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/GLib-2.0.typelib $IPATH/share/gir-1.0/GLib-2.0.gir

# cmake case
sed --in-place -e "s;shared-library=\"\";shared-library=\"libmirage.dll\";" $IPATH/share/gir-1.0/Mirage-3.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Mirage-3.0.typelib $IPATH/share/gir-1.0/Mirage-3.0.gir
sed --in-place -e "s;shared-library=\"\";shared-library=\"libgplugin.dll\";" $IPATH/share/gir-1.0/GPlugin-0.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/GPlugin-0.0.typelib $IPATH/share/gir-1.0/GPlugin-0.0.gir

# gir generated using private lib, before actual lib generated = empty shared-library
sed --in-place -e "s;shared-library=\"\";shared-library=\"libnice-10.dll\";" $IPATH/share/gir-1.0/Nice-0.1.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Nice-0.1.typelib $IPATH/share/gir-1.0/Nice-0.1.gir

# modded library poppler
sed --in-place -e "s;shared-library=\"libpoppler-glib-8.dll,libpoppler-...dll\";shared-library=\"libpoppler-glib-8.dll\";" $IPATH/share/gir-1.0/Poppler-0.18.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Poppler-0.18.typelib $IPATH/share/gir-1.0/Poppler-0.18.gir

# wrong typelib
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Libproxy-1.0.typelib $IPATH/share/gir-1.0/Libproxy-1.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/SQLHeavy-0.2.typelib $IPATH/share/gir-1.0/SQLHeavy-0.2.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Iris-1.0.typelib $IPATH/share/gir-1.0/Iris-1.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/JavaScriptCore-3.0.typelib $IPATH/share/gir-1.0/JavaScriptCore-3.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/WebKit-3.0.typelib $IPATH/share/gir-1.0/WebKit-3.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/WebKit2-3.0.typelib $IPATH/share/gir-1.0/WebKit2-3.0.gir

# vala case, shared-library not supported
sed --in-place -e "s;namespace name=\"Cereal\" version=\"1.0\";namespace name=\"Cereal\" version=\"1.0\" shared-library=\"libcereal-1.dll\";" $IPATH/share/gir-1.0/Cereal-1.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Cereal-1.0.typelib $IPATH/share/gir-1.0/Cereal-1.0.gir
sed --in-place -e "s;namespace name=\"Gee\" version=\"0.8\";namespace name=\"Gee\" version=\"0.8\" shared-library=\"libgee-0.8-2.dll\";" $IPATH/share/gir-1.0/Gee-0.8.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Gee-0.8.typelib $IPATH/share/gir-1.0/Gee-0.8.gir
sed --in-place -e "s;namespace name=\"Aerial\" version=\"1.0\";namespace name=\"Aerial\" version=\"1.0\" shared-library=\"libaerial-0.dll\";" $IPATH/share/gir-1.0/Aerial-1.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Aerial-1.0.typelib $IPATH/share/gir-1.0/Aerial-1.0.gir
sed --in-place -e "s;namespace name=\"GXml\" version=\"0.4\";namespace name=\"GXml\" version=\"0.4\" shared-library=\"libgxml-0.4-4.dll\";" $IPATH/share/gir-1.0/GXml-0.4.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/GXml-0.4.typelib $IPATH/share/gir-1.0/GXml-0.4.gir
sed --in-place -e "s;namespace name=\"Folks\" version=\"0.6\";namespace name=\"Folks\" version=\"0.6\" shared-library=\"libfolks-25.dll\";" $IPATH/share/gir-1.0/Folks-0.6.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Folks-0.6.typelib $IPATH/share/gir-1.0/Folks-0.6.gir
sed --in-place -e "s;namespace name=\"FolksDummy\" version=\"0.6\";namespace name=\"FolksDummy\" version=\"0.6\" shared-library=\"libfolks-dummy-25.dll\";" $IPATH/share/gir-1.0/FolksDummy-0.6.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/FolksDummy-0.6.typelib $IPATH/share/gir-1.0/FolksDummy-0.6.gir
sed --in-place -e "s;namespace name=\"FolksTelepathy\" version=\"0.6\";namespace name=\"FolksTelepathy\" version=\"0.6\" shared-library=\"libfolks-telepathy-25.dll\";" $IPATH/share/gir-1.0/FolksTelepathy-0.6.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/FolksTelepathy-0.6.typelib $IPATH/share/gir-1.0/FolksTelepathy-0.6.gir
sed --in-place -e "s;namespace name=\"libisocodes\" version=\"1.0\";namespace name=\"libisocodes\" version=\"1.0\" shared-library=\"libisocodes-0.dll\";" $IPATH/share/gir-1.0/libisocodes-1.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/libisocodes-1.0.typelib $IPATH/share/gir-1.0/libisocodes-1.0.gir
sed --in-place -e "s;namespace name=\"Skk\" version=\"1.0\";namespace name=\"Skk\" version=\"1.0\" shared-library=\"libskk-0.dll\";" $IPATH/share/gir-1.0/Skk-1.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Skk-1.0.typelib $IPATH/share/gir-1.0/Skk-1.0.gir
sed --in-place -e "s;namespace name=\"FreeSmartphone\" version=\"1.0\";namespace name=\"FreeSmartphone\" version=\"1.0\" shared-library=\"libfso-glib-2.dll\";" $IPATH/share/gir-1.0/FreeSmartphone-1.0.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/FreeSmartphone-1.0.typelib $IPATH/share/gir-1.0/FreeSmartphone-1.0.gir

# wrong namespace version, it's broken but still not a valid version
sed --in-place -e "s;version=\"3.broken\";version=\"3\";" $IPATH/share/gir-1.0/Gcr-3.gir
$IPATH/bin/g-ir-compiler -o $IPATH/lib/girepository-1.0/Gcr-3.typelib $IPATH/share/gir-1.0/Gcr-3.gir
XXX
exit
:<<"XXXX"

# fixme
cd $SPATH/gnome-builder-3.18.1
#configure
#make clean
make $PJOBS
rm $IPATH/lib/*.la

# fixme
cd $SPATH/zenity-3.18.0
configure --enable-libnotify --enable-webkitgtk LIBS="-lmsvcr$2 -lntdll"
make clean
make 
make install
XXXX

if [ "$2" == "90" ]; then
cd $SPATH/gtk+-2.24.28
configure --with-included-immodules --disable-introspection WINDRES="windres $RCFLAGS"
make clean
cd gtk
set +e
rm gtk-update-icon-cache_manifest.o
rm gtk.def
rm gtkbuiltincache.h 
rm stock-icons/icon-theme.cache
set -e
make gtk-update-icon-cache.exe
manifest
cd ..
make $PJOBS
manifest
make install
rm $IPATH/lib/*.la
fi

if [ "$2" == "90" ]; then
cd $SPATH/gtk-engines-2.20.2
configure --disable-static
make clean
make $PJOBS install

cd $SPATH/murrine-0.98.2
configure --disable-static
make clean
make $PJOBS install
cd $SPATH/rezlooks-0.6
configure --disable-static
make clean
make $PJOBS install
cd $SPATH/candido-engine-0.9.1
configure --disable-static
make clean
make $PJOBS install
cd $SPATH/aurora-1.5
configure --disable-static
make clean
make $PJOBS install
cd $SPATH/equinox-1.50
configure --disable-static
make clean
make $PJOBS install

#cd $SPATH/libglade-2.6.4
#configure --disable-static
#make clean
#make $PJOBS install
#rm $IPATH/lib/*.la
#cd $SPATH/glade3-3.8.5
#configure --disable-scrollkeeper --disable-static PYTHON=python27 CPPFLAGS="$CPPFLAGS -I/c/python27/include" LIBS=-lpython2.7 
#make clean
#make $PJOBS
#manifest
#make install
#rm $IPATH/lib/*.la
#cd $SPATH/pygobject-2.28.6
#configure --disable-introspection PYTHON=python27$MULTILIB CPPFLAGS="$CPPFLAGS -I/c/python27/include" LIBS=-lpython2.7 PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$IPATH/py27/lib/pkgconfig" --prefix=$IPATH/py27
#make clean
#make $PJOBS
#make install
#cd $SPATH/pygtk-2.24.0
#configure PYTHON=/usr/bin/python27$MULTILIB CPPFLAGS="$CPPFLAGS -I/c/python27/include -I/c/python27/Lib/site-packages/numpy/core/include" LIBS=-lpython2.7 PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$IPATH/py27/lib/pkgconfig" --prefix=$IPATH/py27
#make clean
#make $PJOBS install
fi

# for libmypaint

exit

#href="http://docs.python.org/2.7/ -> href="../../python2.7/
#href="http://cairographics.org/documentation/pycairo/2/ -> href="../../Pycairo/
#*.html|-hierarchy.html|-mapping.html|-functions.html|-flags.html|-enums.html|-constants.html|-callbacks.html
#href="http://docs.python.org/2.7/ -> href="../python2.7/
#href="http://cairographics.org/documentation/pycairo/2/ -> href="../Pycairo/
#*.html
#\.png" .webp"

#href="C:/Moluccas/local/share/gtk-doc/html/ -> href="../
#*.html

:<<"XXX"
# rebuild manifest for gtk 3.14
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false"></requestedExecutionLevel>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <assemblyIdentity
      version="1.0.0.0"
      processorArchitecture="AMD64"
      name="libgtk3"
      type="win32"
  />
  <dependency>
    <dependentAssembly>
      <assemblyIdentity
          type="win32"
          name="Microsoft.Windows.Common-Controls"
          version="6.0.0.0"
          processorArchitecture="AMD64"
          publicKeyToken="6595b64144ccf1df"
          language="*"
      />
    </dependentAssembly>
  </dependency>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity
          type="win32"
          name="Microsoft.VC90.CRT"
          version="9.0.21022.8"
          processorArchitecture="AMD64"
          publicKeyToken="1fc8b3b9a1e18e3b"
      />
    </dependentAssembly>
  </dependency>
</assembly>

<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false"></requestedExecutionLevel>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <assemblyIdentity
      version="1.0.0.0"
      processorArchitecture="X86"
      name="libgtk3"
      type="win32"
  />
  <dependency>
    <dependentAssembly>
      <assemblyIdentity
          type="win32"
          name="Microsoft.Windows.Common-Controls"
          version="6.0.0.0"
          processorArchitecture="X86"
          publicKeyToken="6595b64144ccf1df"
          language="*"
      />
    </dependentAssembly>
  </dependency>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity
          type="win32"
          name="Microsoft.VC90.CRT"
          version="9.0.21022.8"
          processorArchitecture="X86"
          publicKeyToken="1fc8b3b9a1e18e3b"
      />
    </dependentAssembly>
  </dependency>
</assembly>

XXX
