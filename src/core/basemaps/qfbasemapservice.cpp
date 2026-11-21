/***************************************************************************
 qfbasemapservice.cpp - QfBasemapService

 ---------------------
 begin                : 21.11.2026
 copyright            : (C) 2026 by RTK 外业助手
 email                :
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#include "qfbasemapservice.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#include <qgslayertree.h>
#include <qgslayertreegroup.h>
#include <qgsnetworkaccessmanager.h>
#include <qgsproject.h>
#include <qgsrasterlayer.h>

#include <functional>
#include <utility>

namespace
{
  const QString SERVER_URL_KEY = QStringLiteral( "/basemap/serverUrl" );
  const QString USERNAME_KEY = QStringLiteral( "/basemap/username" );
  const QString PASSWORD_KEY = QStringLiteral( "/basemap/password" );
  const QString TOKEN_KEY = QStringLiteral( "/basemap/token" );
  const QString TIANDITU_KEY = QStringLiteral( "/basemap/tiandituKey" );
  const QString ENABLED_KEY = QStringLiteral( "/basemap/enabled" );
  const QString OPACITY_KEY = QStringLiteral( "/basemap/opacities" );

  const QString LAYER_ID_PROPERTY = QStringLiteral( "qfieldBasemapId" );
  const QString LAYER_GROUP_PROPERTY = QStringLiteral( "qfieldBasemapGroup" );

  const QString JILIN_ONE_URL = QStringLiteral( "jl1/getMap/{z}/{x}/{-y}?mk=2d9bf902749f1630bc25fc720ba7c29f&tk=450daf001884ef53bf77ad46cf5b9e75" );

} // namespace

QfBasemapService::QfBasemapService( QObject *parent )
  : QObject( parent )
{
  loadSettings();
  rebuildBaseEntryTemplates();
  rebuildCatalog();

  connect( QgsProject::instance(), &QgsProject::readProject, this, [this]() {
    // Layers live inside the project, they are gone as soon as another project
    // is loaded: put the user's selection back on top of the new project
    QTimer::singleShot( 0, this, &QfBasemapService::restoreLayers );
  } );
}

QString QfBasemapService::defaultServerUrl()
{
  return QStringLiteral( "https://gis.lankafei1980.top:5443" );
}

void QfBasemapService::setServerUrl( const QString &serverUrl )
{
  QString trimmed = serverUrl.trimmed();
  while ( trimmed.endsWith( '/' ) )
  {
    trimmed.chop( 1 );
  }
  if ( mServerUrl == trimmed )
  {
    return;
  }
  mServerUrl = trimmed;
  emit serverUrlChanged();
  saveSettings();
}

void QfBasemapService::setUsername( const QString &username )
{
  if ( mUsername == username )
  {
    return;
  }
  mUsername = username;
  emit usernameChanged();
  saveSettings();
}

void QfBasemapService::setPassword( const QString &password )
{
  if ( mPassword == password )
  {
    return;
  }
  mPassword = password;
  emit passwordChanged();
  saveSettings();
}

QVariantList QfBasemapService::layers() const
{
  QVariantList result;
  result.reserve( mCatalog.size() );
  for ( const Entry &entry : mCatalog )
  {
    QVariantMap item;
    item.insert( QStringLiteral( "id" ), entry.id );
    item.insert( QStringLiteral( "name" ), entry.name );
    item.insert( QStringLiteral( "group" ), entry.group );
    item.insert( QStringLiteral( "enabled" ), entry.enabled );
    item.insert( QStringLiteral( "opacity" ), entry.opacity );
    result.append( item );
  }
  return result;
}

void QfBasemapService::loadSettings()
{
  QSettings settings;
  mServerUrl = settings.value( SERVER_URL_KEY, defaultServerUrl() ).toString();
  mUsername = settings.value( USERNAME_KEY ).toString();
  mPassword = settings.value( PASSWORD_KEY ).toString();
  mToken = settings.value( TOKEN_KEY ).toString();
  mTiandituKey = settings.value( TIANDITU_KEY ).toString();
  mEnabledIds = settings.value( ENABLED_KEY ).toStringList();
}

void QfBasemapService::saveSettings() const
{
  QSettings settings;
  settings.setValue( SERVER_URL_KEY, mServerUrl );
  settings.setValue( USERNAME_KEY, mUsername );
  settings.setValue( PASSWORD_KEY, mPassword );
  settings.setValue( TOKEN_KEY, mToken );
  settings.setValue( TIANDITU_KEY, mTiandituKey );
  settings.setValue( ENABLED_KEY, mEnabledIds );

  QVariantMap opacities;
  for ( const Entry &entry : mCatalog )
  {
    opacities.insert( entry.id, entry.opacity );
  }
  settings.setValue( OPACITY_KEY, opacities );
}

void QfBasemapService::rebuildBaseEntryTemplates()
{
  // Drop the previously generated base entries, keep the orthophoto ones
  for ( int i = mCatalog.size() - 1; i >= 0; i-- )
  {
    if ( mCatalog.at( i ).group == QLatin1String( "base" ) )
    {
      mCatalog.removeAt( i );
    }
  }

  auto appendBase = [this]( const QString &id, const QString &name, const QString &path ) {
    Entry entry;
    entry.id = id;
    entry.name = name;
    entry.group = QStringLiteral( "base" );
    if ( !mServerUrl.isEmpty() )
    {
      entry.url = mServerUrl + '/' + path;
    }
    entry.zmax = 18;
    entry.enabled = mEnabledIds.contains( id );
    entry.opacity = 1.0;
    mCatalog.append( entry );
  };

  if ( !mTiandituKey.isEmpty() )
  {
    appendBase( QStringLiteral( "tianditu-vec" ), tr( "Tianditu vector" ),
                QStringLiteral( "basemap/DataServer?T=vec_w&x={x}&y={y}&l={z}&tk=%1" ).arg( mTiandituKey ) );
    appendBase( QStringLiteral( "tianditu-cva" ), tr( "Tianditu vector labels" ),
                QStringLiteral( "basemap/DataServer?T=cva_w&x={x}&y={y}&l={z}&tk=%1" ).arg( mTiandituKey ) );
    appendBase( QStringLiteral( "tianditu-img" ), tr( "Tianditu imagery" ),
                QStringLiteral( "basemap/DataServer?T=img_w&x={x}&y={y}&l={z}&tk=%1" ).arg( mTiandituKey ) );
    appendBase( QStringLiteral( "tianditu-cia" ), tr( "Tianditu imagery labels" ),
                QStringLiteral( "basemap/DataServer?T=cia_w&x={x}&y={y}&l={z}&tk=%1" ).arg( mTiandituKey ) );
  }

  appendBase( QStringLiteral( "jl1-img" ), tr( "Jilin-1 satellite" ), JILIN_ONE_URL );

  for ( int i = mCatalog.size() - 1; i >= 0; i-- )
  {
    if ( mCatalog.at( i ).group == QLatin1String( "base" ) && mCatalog.at( i ).url.isEmpty() )
    {
      mCatalog.removeAt( i );
    }
  }
}

void QfBasemapService::rebuildCatalog()
{
  // Read persisted opacities
  QSettings settings;
  const QVariantMap opacities = settings.value( OPACITY_KEY ).toMap();

  for ( Entry &entry : mCatalog )
  {
    entry.enabled = mEnabledIds.contains( entry.id );
    entry.opacity = opacities.value( entry.id, 1.0 ).toDouble();
  }

  emit layersChanged();
}

void QfBasemapService::login()
{
  if ( mServerUrl.isEmpty() )
  {
    setStatus( tr( "Configure the server address first" ) );
    return;
  }
  if ( mUsername.isEmpty() || mPassword.isEmpty() )
  {
    setStatus( tr( "Enter the account and password" ) );
    return;
  }

  setBusy( true );
  QNetworkRequest request( QUrl( mServerUrl + QStringLiteral( "/api/auth/login" ) ) );
  request.setHeader( QNetworkRequest::ContentTypeHeader, QStringLiteral( "application/json" ) );

  QJsonObject payload;
  payload.insert( QStringLiteral( "username" ), mUsername );
  payload.insert( QStringLiteral( "password" ), mPassword );

  QNetworkReply *reply = QgsNetworkAccessManager::instance()->post( request, QJsonDocument( payload ).toJson() );
  connect( reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    setBusy( false );

    if ( reply->error() != QNetworkReply::NoError )
    {
      setStatus( tr( "Connection failed: %1" ).arg( reply->errorString() ) );
      return;
    }

    const QJsonObject object = QJsonDocument::fromJson( reply->readAll() ).object();
    const int code = object.value( QStringLiteral( "code" ) ).toInt();
    if ( code != 200 )
    {
      setStatus( object.value( QStringLiteral( "message" ) ).toString( tr( "Login failed" ) ) );
      return;
    }

    mToken = object.value( QStringLiteral( "data" ) ).toObject().value( QStringLiteral( "token" ) ).toString();
    emit loggedInChanged();
    saveSettings();
    setStatus( tr( "Connected to %1" ).arg( QUrl( mServerUrl ).host() ) );

    fetchSysConfig();
    fetchRasters();
  } );
}

void QfBasemapService::logout()
{
  mToken.clear();
  emit loggedInChanged();
  saveSettings();
  setStatus( tr( "Signed out" ) );
}

void QfBasemapService::refresh()
{
  if ( mToken.isEmpty() )
  {
    login();
    return;
  }
  fetchSysConfig();
  fetchRasters();
}

QByteArray QfBasemapService::tokenHeader() const
{
  return QByteArrayLiteral( "Bearer " ) + mToken.toUtf8();
}

void QfBasemapService::getJson( const QString &path, const std::function<void( const QJsonObject & )> &handler )
{
  QNetworkRequest request( QUrl( mServerUrl + path ) );
  request.setRawHeader( QByteArrayLiteral( "Authorization" ), tokenHeader() );

  QNetworkReply *reply = QgsNetworkAccessManager::instance()->get( request );
  connect( reply, &QNetworkReply::finished, this, [this, reply, handler]() {
    reply->deleteLater();
    if ( reply->error() != QNetworkReply::NoError )
    {
      setStatus( tr( "Request failed: %1" ).arg( reply->errorString() ) );
      return;
    }
    const QJsonObject object = QJsonDocument::fromJson( reply->readAll() ).object();
    if ( object.value( QStringLiteral( "code" ) ).toInt() != 200 )
    {
      setStatus( object.value( QStringLiteral( "message" ) ).toString( tr( "Server refused the request" ) ) );
      return;
    }
    handler( object );
  } );
}

void QfBasemapService::fetchSysConfig()
{
  getJson( QStringLiteral( "/api/sys-config" ), [this]( const QJsonObject &object ) {
    const QString key = object.value( QStringLiteral( "data" ) ).toObject().value( QStringLiteral( "tianditu_tk" ) ).toString();
    if ( key.isEmpty() || key == mTiandituKey )
    {
      return;
    }
    mTiandituKey = key;
    saveSettings();
    rebuildBaseEntryTemplates();
    rebuildCatalog();
    restoreLayers();
  } );
}

void QfBasemapService::fetchRasters()
{
  getJson( QStringLiteral( "/api/upload/rasters" ), [this]( const QJsonObject &object ) {
    for ( int i = mCatalog.size() - 1; i >= 0; i-- )
    {
      if ( mCatalog.at( i ).group == QLatin1String( "ortho" ) )
      {
        mCatalog.removeAt( i );
      }
    }

    const QJsonArray rasters = object.value( QStringLiteral( "data" ) ).toArray();
    for ( const QJsonValue &value : rasters )
    {
      const QString name = value.toObject().value( QStringLiteral( "name" ) ).toString();
      if ( name.isEmpty() )
      {
        continue;
      }
      Entry entry;
      QString displayName = name;
      displayName.remove( QStringLiteral( "_cog.tif" ) );
      displayName.remove( QStringLiteral( ".tif" ) );
      entry.id = QStringLiteral( "ortho:" ) + name;
      entry.name = tr( "Orthophoto: %1" ).arg( displayName );
      entry.group = QStringLiteral( "ortho" );
      entry.url = mServerUrl
                  + QStringLiteral( "/titiler/cog/tiles/WebMercatorQuad/{z}/{x}/{y}@2x.webp?url=/data/" )
                  + QString::fromLatin1( QUrl::toPercentEncoding( name ) );
      entry.zmax = 22;
      entry.enabled = mEnabledIds.contains( entry.id );
      mCatalog.append( entry );
    }

    rebuildCatalog();
    restoreLayers();
    setStatus( tr( "%1 orthophoto(s) available" ).arg( rasters.size() ) );
  } );
}

QString QfBasemapService::entryUri( const Entry &entry ) const
{
  if ( entry.url.isEmpty() )
  {
    return QString();
  }

  QString url = entry.url;
  if ( !url.startsWith( QLatin1String( "http" ) ) )
  {
    url = mServerUrl + '/' + url;
  }

  return QStringLiteral( "type=xyz&url=%1&zmin=0&zmax=%2" )
    .arg( QString::fromLatin1( QUrl::toPercentEncoding( url ) ), QString::number( entry.zmax ) );
}

QString QfBasemapService::creationUri( const QString &id ) const
{
  for ( const Entry &entry : mCatalog )
  {
    if ( entry.id == id )
    {
      return entryUri( entry );
    }
  }
  return QString();
}

void QfBasemapService::addEntryLayer( const QString &id )
{
  if ( QgsProject::instance() == nullptr )
  {
    return;
  }

  const Entry *entry = nullptr;
  for ( const Entry &candidate : mCatalog )
  {
    if ( candidate.id == id )
    {
      entry = &candidate;
      break;
    }
  }
  if ( entry == nullptr || entry->url.isEmpty() )
  {
    return;
  }

  const QString uri = entryUri( *entry );
  if ( uri.isEmpty() )
  {
    return;
  }

  QgsRasterLayer *layer = new QgsRasterLayer( uri, entry->name, QStringLiteral( "wms" ) );
  if ( !layer->isValid() )
  {
    setStatus( tr( "Could not load \"%1\"" ).arg( entry->name ) );
    delete layer;
    return;
  }

  layer->setCustomProperty( LAYER_ID_PROPERTY, entry->id );
  layer->setCustomProperty( LAYER_GROUP_PROPERTY, entry->group );
  layer->setOpacity( entry->opacity );

  QgsProject::instance()->addMapLayer( layer, false );
  QgsLayerTreeGroup *root = QgsProject::instance()->layerTreeRoot();

  int index = root->children().size();
  if ( entry->group == QLatin1String( "ortho" ) )
  {
    int basemapCount = 0;
    const QMap<QString, QgsMapLayer *> layers = QgsProject::instance()->mapLayers();
    for ( QgsMapLayer *candidate : layers )
    {
      if ( candidate->customProperty( LAYER_GROUP_PROPERTY ).toString() == QLatin1String( "base" ) )
      {
        basemapCount++;
      }
    }
    index = qMax( 0, index - basemapCount );
  }
  root->insertLayer( index, layer );
}

void QfBasemapService::removeEntryLayer( const QString &id )
{
  if ( QgsProject::instance() == nullptr )
  {
    return;
  }

  QStringList layerIds;
  const QMap<QString, QgsMapLayer *> layers = QgsProject::instance()->mapLayers();
  for ( QgsMapLayer *candidate : layers )
  {
    if ( candidate->customProperty( LAYER_ID_PROPERTY ).toString() == id )
    {
      layerIds.append( candidate->id() );
    }
  }
  for ( const QString &layerId : layerIds )
  {
    QgsProject::instance()->removeMapLayer( layerId );
  }
}

void QfBasemapService::restoreLayers()
{
  // Remove everything we previously injected, then re-add the current selection
  QStringList ourLayerIds;
  const QMap<QString, QgsMapLayer *> layers = QgsProject::instance()->mapLayers();
  for ( QgsMapLayer *candidate : layers )
  {
    if ( !candidate->customProperty( LAYER_ID_PROPERTY ).toString().isEmpty() )
    {
      ourLayerIds.append( candidate->id() );
    }
  }
  for ( const QString &layerId : ourLayerIds )
  {
    QgsProject::instance()->removeMapLayer( layerId );
  }

  for ( const QString &id : std::as_const( mEnabledIds ) )
  {
    addEntryLayer( id );
  }
}

void QfBasemapService::setLayerEnabled( const QString &id, bool enabled )
{
  bool found = false;
  for ( Entry &entry : mCatalog )
  {
    if ( entry.id == id )
    {
      entry.enabled = enabled;
      found = true;
      break;
    }
  }
  if ( !found )
  {
    return;
  }

  if ( enabled )
  {
    if ( !mEnabledIds.contains( id ) )
    {
      mEnabledIds.append( id );
    }
    addEntryLayer( id );
  }
  else
  {
    mEnabledIds.removeAll( id );
    removeEntryLayer( id );
  }

  saveSettings();
  emit layersChanged();
}

void QfBasemapService::setLayerOpacity( const QString &id, double opacity )
{
  opacity = qBound( 0.0, opacity, 1.0 );
  for ( Entry &entry : mCatalog )
  {
    if ( entry.id != id )
    {
      continue;
    }
    entry.opacity = opacity;

    const QMap<QString, QgsMapLayer *> layers = QgsProject::instance()->mapLayers();
    for ( QgsMapLayer *candidate : layers )
    {
      if ( candidate->customProperty( LAYER_ID_PROPERTY ).toString() == id )
      {
        candidate->setOpacity( opacity );
      }
    }
    saveSettings();
    emit layersChanged();
    return;
  }
}

void QfBasemapService::setBusy( bool busy )
{
  if ( mBusy == busy )
  {
    return;
  }
  mBusy = busy;
  emit busyChanged();
}

void QfBasemapService::setStatus( const QString &message )
{
  if ( mStatusMessage == message )
  {
    return;
  }
  mStatusMessage = message;
  qInfo() << "BasemapService:" << message;
  emit statusMessageChanged();
}
