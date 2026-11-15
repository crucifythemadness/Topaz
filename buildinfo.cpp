#include "buildinfo.h"
#include "topaz_build_date.h"   // generated, see cmake/WriteBuildDate.cmake
#include "codestats.h"          // tools/count-loc.ps1, refreshed once per release

QString BuildInfo::version() const
{
    return QStringLiteral(TOPAZ_VERSION_STRING);
}

QString BuildInfo::buildDate() const
{
    // Not __DATE__: that is only refreshed when this file itself recompiles,
    // so the About dialog kept showing an old day.
    return QStringLiteral(TOPAZ_BUILD_DATE);
}

QString BuildInfo::qtVersion() const
{
    return QString::fromLatin1(qVersion());
}

int BuildInfo::topazLines() const
{
    return TOPAZ_CODE_LINES;
}

int BuildInfo::thirdPartyLines() const
{
    return TOPAZ_THIRD_PARTY_LINES;
}
