#include "buildinfo.h"

QString BuildInfo::version() const
{
    return QStringLiteral(TOPAZ_VERSION_STRING);
}

QString BuildInfo::buildDate() const
{
    return QStringLiteral(__DATE__);
}
