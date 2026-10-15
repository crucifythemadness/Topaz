#include "buildinfo.h"
#include "topaz_build_date.h"   // generated, see cmake/WriteBuildDate.cmake

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
