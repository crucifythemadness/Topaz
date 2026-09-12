#include "hiresaudiologo.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QUrl>

HiResAudioLogo::HiResAudioLogo(QObject *parent) : QObject(parent) {}

QString HiResAudioLogo::url() const
{
    const QString path = QCoreApplication::applicationDirPath()
                          + QStringLiteral("/Hi-Res_Audio.svg");
    if (!QFileInfo::exists(path)) return QString();
    return QUrl::fromLocalFile(path).toString();
}
