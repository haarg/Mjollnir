!tempfile DISTPARAM
!system 'cd .. && Build.bat distclean'
!delfile ..\MANIFEST
!system 'cd .. && perl Build.PL'
!system 'cd .. && Build.bat manifest'
!system 'cd .. && Build.bat distdir'
!system 'perl -MParse::CPAN::Meta=LoadFile -e"print LoadFile(shift)->{name}" ..\META.yml > ${DISTPARAM}'
!define /file DISTNAME ${DISTPARAM}
!system 'perl -MParse::CPAN::Meta=LoadFile -e"print LoadFile(shift)->{version}" ..\META.yml > ${DISTPARAM}'
!define /file DISTVERSION ${DISTPARAM}
!delfile ${DISTPARAM}
!undef DISTPARAM

!define DISTDIR "..\${DISTNAME}-${DISTVERSION}"

Name "${DISTNAME}"
OutFile "${DISTNAME}-${DISTVERSION}-installer.exe"

RequestExecutionLevel admin
ShowInstDetails show
SetCompressor lzma

!include "LogicLib.nsh"
!include "WinVer.nsh"
!include "MUI2.nsh"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function .onInit
    ${IfNot} ${AtLeastWinXP}
        MessageBox MB_OK|MB_ICONSTOP "Windows XP or greater required"
        Abort
    ${EndIf}
FunctionEnd

Section ""
    InitPluginsDir
    SetOutPath $PLUGINSDIR

    Var /GLOBAL install_ipseccmd
    Var /GLOBAL install_perl

    ${If} ${IsWinXP}
        nsExec::ExecToStack "ipseccmd"
        Pop $R0
        ${If} $R0 == "error"
            StrCpy $install_ipseccmd 1
            NSISdl::download http://download.microsoft.com/download/d/3/8/d38066aa-4e37-4ae8-bce3-a4ce662b2024/WindowsXP-KB838079-SupportTools-ENU.exe "WindowsXP-KB838079-SupportTools-ENU.exe"
            Pop $R0
            ${If} $R0 != "success"
                Abort
            ${EndIf}
        ${EndIf}
    ${EndIf}

    nsExec::ExecToStack "C:\strawberry\perl\bin\perl.exe -V"
    Pop $R0
    ${If} $R0 == "error"
        StrCpy $install_perl 1
        NSISdl::download http://strawberry-perl.googlecode.com/files/strawberry-perl-5.10.1.1.msi "strawberry-perl-5.10.1.1.msi"
        Pop $R0
        ${If} $R0 != "success"
            Abort
        ${EndIf}
    ${EndIf}

    File winpcap-nmap-4.11.exe
    File /r ${DISTDIR}\*.*

    ${If} $install_ipseccmd == 1
        DetailPrint "Installing Windows XP SP2 Support Tools..."
        ExecWait '"$PLUGINSDIR\WindowsXP-KB838079-SupportTools-ENU.exe" /Q /C:"msiexec.exe /qb /i suptools.msi REBOOT=ReallySuppress ADDLOCAL=ALL"'
    ${EndIf}
    ${If} $install_perl == 1
        DetailPrint "Installing Strawberry Perl..."
        ExecWait 'msiexec.exe /qb /i "$PLUGINSDIR\strawberry-perl-5.10.1.1.msi"'
        ReadEnvStr $R0 "PATH"
        StrCpy $R0 "C:\strawberry\c\bin;C:\strawberry\perl\bin;$R0"
        System::Call 'Kernel32::SetEnvironmentVariableA(t, t) i("PATH", R0).r0'
    ${EndIf}

    DetailPrint "Installing WinPcap..."
    ExecWait '"$PLUGINSDIR\winpcap-nmap-4.11.exe" /S'

    StrCpy $R0 $PLUGINSDIR\.cpanm
    System::Call 'Kernel32::SetEnvironmentVariableA(t, t) i("PERL_CPANM_HOME", R0).r0'
    File C:\strawberry\perl\bin\cpanm

    DetailPrint "Installing CPAN Prerequisites..."
    nsExec::ExecToLog 'C:\strawberry\perl\bin\perl.exe C:\strawberry\perl\bin\ppm.pl install Net::Pcap'

    nsExec::ExecToLog 'C:\strawberry\perl\bin\perl.exe cpanm -n EV'
    nsExec::ExecToLog 'C:\strawberry\perl\bin\perl.exe cpanm -n --installdeps .'
    DetailPrint "Installing Mjollnir..."
    nsExec::ExecToLog 'C:\strawberry\perl\bin\perl.exe cpanm -n .'

    SetOutPath $SYSDIR
    CreateShortcut "$DESKTOP\Mjollnir.lnk" C:\strawberry\perl\bin\perl.exe C:\strawberry\perl\bin\mjollnir.pl "$SYSDIR\shell32.dll" 10
SectionEnd
