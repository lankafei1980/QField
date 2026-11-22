/***************************************************************************
 qfbasemapservice.h - QfBasemapService

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

#ifndef QFBASEMAPSERVICE_H
#define QFBASEMAPSERVICE_H

#include <QByteArray>
#include <QObject>
#include <QString>
#include <QVariantList>

#include <functional>

class QJsonObject;

/**
 * \brief Fetches basemaps / orthophotos / vector catalogues from an online GIS
 *        service (the "NEWGIS" platform) and exposes them as XYZ map layers.
 *
 * The service is configured from the app settings: server URL, account and
 * password. Once logged in, it asks the server for the Tianditu key and the
 * orthophoto (COG) list, then lets the user toggle any of those layers in the
 * map. Enabled layers and their opacity are remembered.
 *
 * \ingroup core
 */
class QfBasemapService : public QObject
{
    Q_OBJECT

    Q_PROPERTY( QString serverUrl READ serverUrl WRITE setServerUrl NOTIFY serverUrlChanged )
    Q_PROPERTY( QString username READ username WRITE setUsername NOTIFY usernameChanged )
    Q_PROPERTY( QString password READ password WRITE setPassword NOTIFY passwordChanged )
    Q_PROPERTY( bool loggedIn READ loggedIn NOTIFY loggedInChanged )
    Q_PROPERTY( bool busy READ busy NOTIFY busyChanged )
    Q_PROPERTY( QString statusMessage READ statusMessage NOTIFY statusMessageChanged )
    Q_PROPERTY( QVariantList layers READ layers NOTIFY layersChanged )
    Q_PROPERTY( bool googleAvailable READ googleAvailable NOTIFY layersChanged )

  public:
    explicit QfBasemapService( QObject *parent = nullptr );

    QString serverUrl() const { return mServerUrl; }
    void setServerUrl( const QString &serverUrl );

    QString username() const { return mUsername; }
    void setUsername( const QString &username );

    QString password() const { return mPassword; }
    void setPassword( const QString &password );

    bool loggedIn() const { return !mToken.isEmpty(); }
    bool busy() const { return mBusy; }
    QString statusMessage() const { return mStatusMessage; }
    QVariantList layers() const;
    bool googleAvailable() const { return mGoogleEnabled; }

    //! Authenticates against the configured server and loads its catalogue
    Q_INVOKABLE void login();

    //! Drops the session token (keeps the layers on the map)
    Q_INVOKABLE void logout();

    //! Reloads the Tianditu key and the orthophoto list from the server
    Q_INVOKABLE void refresh();

    //! Adds or removes one catalog entry from the map
    Q_INVOKABLE void setLayerEnabled( const QString &id, bool enabled );

    //! Sets the opacity (0..1) of one catalog entry and persists it
    Q_INVOKABLE void setLayerOpacity( const QString &id, double opacity );

    //! Updates the opacity of one catalog entry without persisting or notifying
    //! (used while the user drags the opacity slider)
    Q_INVOKABLE void setLayerOpacityLive( const QString &id, double opacity );

    //! Sorts the injected basemap layers below the project layers: satellite
    //! imagery at the bottom, then orthophotos, vector basemaps and labels.
    Q_INVOKABLE void sortLayers();

    //! Temporarily raises a layer being edited within its parent group.
    Q_INVOKABLE void raiseDrawingLayer( const QString &layerId );

    //! Restores the layer raised by raiseDrawingLayer().
    Q_INVOKABLE void restoreDrawingLayer();

    /**
     * Returns an encoded QGIS layer URI for one catalog entry, or an empty
     * string when the entry is not available (e.g. no Tianditu key yet). Used
     * by the project creation screen to embed an online basemap in a brand new
     * project.
     */
    Q_INVOKABLE QString creationUri( const QString &id ) const;

  signals:
    void serverUrlChanged();
    void usernameChanged();
    void passwordChanged();
    void loggedInChanged();
    void busyChanged();
    void statusMessageChanged();
    void layersChanged();

    //! Emitted after a layer tree reorder, so the flat layer tree model can be
    //! rebuilt (its row map does not support arbitrary moves).
    void layersReordered();

  private:
    struct Entry
    {
        QString id;
        QString name;
        QString group; // "base" or "ortho"
        QString url;   // XYZ template, may contain {z}/{x}/{y}/{-y}
        int zmax = 19;
        bool enabled = false;
        double opacity = 1.0;
    };

    void loadSettings();
    void saveSettings() const;
    void rebuildBaseEntryTemplates();
    void rebuildCatalog();
    void fetchSysConfig();
    void fetchRasters();
    void applyLayerOpacity( const QString &id, double opacity, bool commit );
    void applyLayerOrder();
    QString entryUri( const Entry &entry ) const;
    void addEntryLayer( const QString &id );
    void removeEntryLayer( const QString &id );
    void restoreLayers();
    void resetLayers();
    void setBusy( bool busy );
    void setStatus( const QString &message );

    QByteArray tokenHeader() const;
    void getJson( const QString &path, const std::function<void( const QJsonObject & )> &handler );

    QString mServerUrl;
    QString mUsername;
    QString mPassword;
    QString mToken;
    QString mTiandituKey;
    QString mStatusMessage;
    bool mBusy = false;
    bool mGoogleEnabled = false;

    // Layer temporarily raised while editing (restored when editing stops).
    QString mRaisedLayerId;
    int mRaisedIndex = -1;

    QList<Entry> mCatalog;
    QStringList mEnabledIds;

    static QString defaultServerUrl();
};

#endif // QFBASEMAPSERVICE_H
