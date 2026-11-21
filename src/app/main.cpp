/***************************************************************************
                            main.cpp  -  main for qgis mobileapp
                            based on src/browser/main.cpp
                              -------------------
              begin                : Wed Apr 04 10:48:28 CET 2012
              copyright            : (C) 2012 by Marco Bernasocchi
              email                : marco@bernawebdesign.ch
 ***************************************************************************/

/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

#include "qfield.h"
#include "qfplatformutilities.h"
#include "qftranslatormanager.h"
#include "qgismobileapp.h"
#if WITH_SENTRY
#include "sentry_wrapper.h"
#endif

#if defined( Q_OS_ANDROID )
#include "qfieldcloudservice.h"
#include "qfieldpositioningservice.h"
#endif

#include <qgsapplication.h>
#include <qgsauthmanager.h>
#include <qgslogger.h>
#include <qgsprojutils.h>
#include <qgsstyle.h>

#ifdef WITH_SPIX
#include <Spix/AnyRpcServer.h>
#include <Spix/QtQmlBot.h>
#endif

#include <QApplication>
#include <QDialog>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QLabel>
#include <QLocale>
#include <QMainWindow>
#include <QNetworkDiskCache>
#include <QSettings>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QStandardPaths>
#include <QTranslator>
#include <QtWebView/QtWebView>
#include <qgsnetworkaccessmanager.h>

#include <proj.h>

#if HAVE_STATIC_QCA_PLUGINS
#include <QtPlugin>
Q_IMPORT_PLUGIN( opensslPlugin )
#endif

void initGraphics()
{
  QCoreApplication::setAttribute( Qt::AA_DisableShaderDiskCache );

#ifdef WITH_SPIX
  // Set antialiasing method to vertex to get same antialiasing across environments
  qputenv( "QSG_ANTIALIASING_METHOD", "vertex" );

  QSurfaceFormat format;
  format.setSamples( 4 );
  QSurfaceFormat::setDefaultFormat( format );
#endif
}

void initAuthManager( QgsAuthManager *authManager )
{
#ifndef Q_OS_LINUX
  if ( authManager->verifyMasterPassword( QStringLiteral( "qfield" ) ) )
  {
    // migrating authentication database
    authManager->setPasswordHelperEnabled( false );
    authManager->setMasterPassword( QStringLiteral( "qfield" ) );
    authManager->setPasswordHelperEnabled( true );

    QRandomGenerator generator = QRandomGenerator::securelySeeded();
    QString pw;
    pw.resize( 32 );
    static const QString sPwChars = QStringLiteral( "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_-{}[]" );
    for ( int i = 0; i < pw.size(); ++i )
    {
      pw[i] = sPwChars.at( generator.bounded( 0, sPwChars.length() ) );
    }

    authManager->resetMasterPassword( pw, QStringLiteral( "qfield" ), false );
    authManager->passwordHelperSync();
  }

  if ( !authManager->masterPasswordHashInDatabase() )
  {
    // if no master password set by user yet, just generate a new one and store it in the system keychain
    authManager->createAndStoreRandomMasterPasswordInKeyChain();
  }
#else
  authManager->setPasswordHelperEnabled( false );
  authManager->setMasterPassword( QStringLiteral( "qfield" ) );
#endif
}

int main( int argc, char **argv )
{
  qputenv( "QT_ANDROID_DISABLE_ACCESSIBILITY", "1" );

  QCoreApplication::setOrganizationName( "OPENGIS.ch" );
  QCoreApplication::setOrganizationDomain( "opengis.ch" );
  QCoreApplication::setApplicationName( Qfield::appName );

#if defined( Q_OS_ANDROID )
  if ( argc > 1 )
  {
    if ( strcmp( argv[1], "--cloudservice" ) == 0 )
    {
      // This service only deals with background attachment uploads;
      // it will terminate once all uploads are done
      QFieldCloudService service( argc, argv );

      QfPlatformUtilities *platformUtils = QfPlatformUtilities::instance();
      platformUtils->initSystem();

      // Let's make sure we have a writable path for the QGIS profile on every platform
      const QString profilePath = platformUtils->systemLocalDataLocation( QStringLiteral( "profiles/default" ) );
      QDir().mkdir( profilePath );

#ifdef RELATIVE_PREFIX_PATH
      qputenv( "SSL_CERT_FILE", QDir::toNativeSeparators( QfPlatformUtilities::instance()->systemSharedDataLocation() + "/cacert.pem" ).toLocal8Bit() );
      qputenv( "GDAL_DATA", QDir::toNativeSeparators( QfPlatformUtilities::instance()->systemSharedDataLocation() + "/gdal" ).toLocal8Bit() );
#endif

      // Workaround QgsApplication::initQgis crashing adding app fonts
      QDir profileDir( profilePath );
      profileDir.rename( QStringLiteral( "fonts" ), QStringLiteral( "fonts-disabled" ) );

      QgsApplication::init( profilePath );
      QgsApplication::initQgis();
#ifdef RELATIVE_PREFIX_PATH
      QgsApplication::setPkgDataPath( QfPlatformUtilities::instance()->systemSharedDataLocation() + QStringLiteral( "/qgis" ) );
#endif
      QgsApplication::createDatabase();
      initAuthManager( QgsApplication::authManager() );

      profileDir.rmdir( QStringLiteral( "fonts" ) );
      profileDir.rename( QStringLiteral( "fonts-disabled" ), QStringLiteral( "fonts" ) );

      service.initService();
      return service.exec();
    }
    else if ( strcmp( argv[1], "--positioningservice" ) == 0 )
    {
      QFieldPositioningService service( argc, argv );
      return service.exec();
    }
  }
#endif

  initGraphics();

  // Read settings, use a dummy app to get access to QSettings
  QCoreApplication *dummyApp = new QCoreApplication( argc, argv );
  QSettings settings;

  QString customLanguage = settings.value( "/customLanguage", QString() ).toString();

  // Some builds target a single market and want the UI translated out of the
  // box even when the device runs another system language. The build default is
  // applied once, on the very first start, and the user can always switch back
  // to "system" from the app settings afterwards.
  const QString buildDefaultLanguage = QStringLiteral( "@APP_DEFAULT_LANGUAGE@" );
  if ( customLanguage.isEmpty() && !buildDefaultLanguage.isEmpty()
       && !settings.contains( "/customLanguageInitialized" ) )
  {
    settings.setValue( "/customLanguageInitialized", true );
    if ( QLocale().language() != QLocale( buildDefaultLanguage ).language() )
    {
      customLanguage = buildDefaultLanguage;
      settings.setValue( "/customLanguage", customLanguage );
    }
    settings.sync();
  }

  QfPlatformUtilities *platformUtils = QfPlatformUtilities::instance();
  platformUtils->initSystem();

#if defined( Q_OS_ANDROID )
  // The private basemap server (NEWGIS) uses a certificate issued by a private
  // CA. Trust that CA (bundled as a resource) and, because QGIS/Qt may reset
  // the default SSL configuration while initialising, also allow skipping the
  // certificate verification for this internal build.
  const auto installBundledCa = [&settings]() {
    QSslConfiguration sslConfig = QSslConfiguration::defaultConfiguration();

    QFile caFile( QStringLiteral( ":/ca/newgis-ca.pem" ) );
    if ( caFile.open( QIODevice::ReadOnly ) )
    {
      const QList<QSslCertificate> extraCerts = QSslCertificate::fromData( caFile.readAll(), QSsl::Pem );
      if ( extraCerts.isEmpty() )
      {
        qWarning() << "SSL: bundled NEWGIS CA could not be parsed";
      }
      else
      {
        QList<QSslCertificate> certs = sslConfig.caCertificates();
        certs.append( extraCerts );
        sslConfig.setCaCertificates( certs );
        qInfo() << "SSL: bundled CA certificates" << extraCerts.size() << "total trusted" << certs.size();
      }
    }
    else
    {
      qWarning() << "SSL: bundled NEWGIS CA resource is missing";
    }

    // An internal deployment with a private CA: verification can be turned off
    // from the basemap settings, it defaults to on for this build.
    if ( settings.value( QStringLiteral( "/basemap/trustCertificate" ), true ).toBool() )
    {
      sslConfig.setPeerVerifyMode( QSslSocket::VerifyNone );
      qInfo() << "SSL: peer certificate verification disabled (internal server)";
    }

    QSslConfiguration::setDefaultConfiguration( sslConfig );
  };
  installBundledCa();
#endif

#if defined( RELATIVE_PREFIX_PATH ) && defined( Q_OS_IOS )
  const QList<QSslCertificate> certs = QSslCertificate::fromPath( QDir::toNativeSeparators( QfPlatformUtilities::instance()->systemSharedDataLocation() + "/cacert.pem" ) );
  QSslConfiguration sslConfig = QSslConfiguration::defaultConfiguration();
  sslConfig.setCaCertificates( certs );
  QSslConfiguration::setDefaultConfiguration( sslConfig );
#endif

  // Let's make sure we have a writable path for the QGIS profile on every platform
  const QString profilePath = platformUtils->systemLocalDataLocation( QStringLiteral( "profiles/default" ) );
  QDir().mkdir( profilePath );

#if WITH_SENTRY
  const bool enableSentry = settings.value( "/enableInfoCollection", true ).toBool();
  if ( enableSentry )
    sentry_wrapper::init();
  // Make sure everything flushes when exiting the app
  auto sentryClose = qScopeGuard( [] { sentry_wrapper::close(); } );
#endif

  QTranslator *qfieldTranslator = QfTranslatorManager::instance()->qfieldTranslator();
  QTranslator *qtTranslator = QfTranslatorManager::instance()->qtTranslator();
  bool qfieldTranslatorLoaded = false;
  bool qtTranslatorLoaded = false;
  if ( !customLanguage.isEmpty() )
  {
    qfieldTranslatorLoaded = qfieldTranslator->load( QStringLiteral( "qfield_%1" ).arg( customLanguage ), QStringLiteral( ":/i18n/" ), "_" );
    qtTranslatorLoaded = qtTranslator->load( QStringLiteral( "qt_%1" ).arg( customLanguage ), QStringLiteral( ":/i18n/" ), "_" );
  }
  dummyApp->installTranslator( qtTranslator );
  dummyApp->installTranslator( qfieldTranslator );

  delete dummyApp;

  QtWebView::initialize();

  QgsApplication app( argc, argv, true, profilePath, QStringLiteral( "mobile" ) );

#if defined( Q_OS_ANDROID )
  // QgsApplication touches the SSL configuration while initialising, re-apply
  // the bundled CA afterwards so that requests created later on trust it
  installBundledCa();

  // Map tiles are the bulk of the network traffic: give the network disk cache
  // a size that can actually hold a survey area's worth of tiles
  if ( QNetworkDiskCache *networkCache = qobject_cast<QNetworkDiskCache *>( QgsNetworkAccessManager::instance()->cache() ) )
  {
    networkCache->setMaximumCacheSize( 256LL * 1024 * 1024 );
    qInfo() << "Network cache size set to" << networkCache->maximumCacheSize() << "bytes";
  }
#endif

  if ( !qfieldTranslatorLoaded || qfieldTranslator->isEmpty() )
  {
    ( void ) qfieldTranslator->load( QStringLiteral( "qfield_%1" ).arg( QLocale().name() ), QStringLiteral( ":/i18n/" ), "_" );
  }
  if ( !qtTranslatorLoaded || qtTranslator->isEmpty() )
  {
    ( void ) qtTranslator->load( QStringLiteral( "qt_%1" ).arg( QLocale().name() ), QStringLiteral( ":/i18n/" ), "_" );
  }

  if ( !customLanguage.isEmpty() )
  {
    QLocale customLocale( customLanguage );
    QLocale::setDefault( customLocale );
    QgsApplication::setTranslation( customLanguage );
    QgsApplication::setLocale( QLocale() ); // Set locale to emit QgsApplication's localeChanged signal
  }

  const QString qfieldFontName( qgetenv( "QFIELD_FONT_NAME" ) );
  if ( !qfieldFontName.isEmpty() )
  {
    const QString qfieldFont( qgetenv( "QFIELD_FONT_TTF" ) );
    const int qfieldFontSize = QString( qgetenv( "QFIELD_FONT_SIZE" ) ).toInt();
    QFontDatabase::addApplicationFont( qfieldFont );
    app.setFont( QFont( qfieldFontName, qfieldFontSize ) );
  }

  QStringList projSearchPaths = QgsProjUtils::searchPaths();
#ifdef RELATIVE_PREFIX_PATH
  qputenv( "SSL_CERT_FILE", QDir::toNativeSeparators( QfPlatformUtilities::instance()->systemSharedDataLocation() + "/cacert.pem" ).toLocal8Bit() );
  qputenv( "GDAL_DATA", QDir::toNativeSeparators( QfPlatformUtilities::instance()->systemSharedDataLocation() + "/gdal" ).toLocal8Bit() );
  projSearchPaths << QDir::toNativeSeparators( QfPlatformUtilities::instance()->systemSharedDataLocation() + "/proj" );
  qInfo() << "Proj path: " << projSearchPaths.constLast();
#else
  app.setPrefixPath( QGIS_PREFIX_PATH, true );
  qInfo() << "Proj path: {System}";
#endif

  // add extra proj search path to allow copying of transformation grid files
  const QStringList dataDirs = QfPlatformUtilities::instance()->appDataDirs();
  for ( const QString &dataDir : dataDirs )
  {
    projSearchPaths << QStringLiteral( "%1/proj/" ).arg( dataDir );
  }

  if ( !projSearchPaths.isEmpty() )
  {
    char **newPaths = new char *[projSearchPaths.count()];
    for ( int i = 0; i < projSearchPaths.count(); ++i )
    {
      newPaths[i] = strdup( projSearchPaths.at( i ).toUtf8().constData() );
    }
    proj_context_set_search_paths( nullptr, static_cast<int>( projSearchPaths.count() ), newPaths );
    for ( int i = 0; i < projSearchPaths.count(); ++i )
    {
      free( newPaths[i] );
    }
    delete[] newPaths;
  }

#if defined( Q_OS_ANDROID ) || defined( Q_OS_IOS )
  for ( const QString &dataDir : dataDirs )
  {
    const QFileInfo pgServiceFileInfo( QStringLiteral( "%1/pg_service.conf" ).arg( dataDir ) );
    if ( pgServiceFileInfo.exists() && pgServiceFileInfo.isReadable() )
    {
      const QString systemLocalDataPath = platformUtils->systemLocalDataLocation( QString() );

      QFile pgServiceFile( QStringLiteral( "%1/pg_service.conf" ).arg( dataDir ) );
      if ( pgServiceFile.open( QFile::ReadOnly | QFile::Text ) )
      {
        QTextStream textStream( &pgServiceFile );
        QString psServiceFileContent = textStream.readAll();
        pgServiceFile.close();

        const QStringList keys = QStringList() << QStringLiteral( "sslrootcert" ) << QStringLiteral( "sslcert" ) << QStringLiteral( "sslkey" );
        for ( const QString &key : keys )
        {
          const QRegularExpression rx( QStringLiteral( "%1=(.*)" ).arg( key ) );
          QRegularExpressionMatchIterator matchIt = rx.globalMatch( psServiceFileContent );
          while ( matchIt.hasNext() )
          {
            const QRegularExpressionMatch match = matchIt.next();
            const QString fileName = match.captured( 1 ).trimmed();

            // Check if the file is relative to the pg_service.conf, in which case copy to user-owned location, use absolute path, and change permissions
            const QString filePath = QStringLiteral( "%1/%2" ).arg( dataDir, fileName );
            const QFileInfo fileInfo( filePath );
            if ( QFileInfo::exists( filePath ) )
            {
              const QString newFilePath = QStringLiteral( "%1/%2" ).arg( systemLocalDataPath, fileName );
              if ( QFileInfo::exists( newFilePath ) )
              {
                QFile newFile( newFilePath );
                newFile.remove();
              }
              QFile::copy( filePath, newFilePath );
              QFile::setPermissions( newFilePath, QFileDevice::ReadOwner | QFileDevice::WriteOwner );
              psServiceFileContent.replace( QStringLiteral( "%1=%2" ).arg( key, match.captured( 1 ) ), QStringLiteral( "%1=%2" ).arg( key, newFilePath ) );
            }
          }
        }

        const QString localPgServiceFileName = QStringLiteral( "%1/pg_service.conf" ).arg( systemLocalDataPath );
        QFile localPgServiceFile( localPgServiceFileName );
        if ( localPgServiceFile.open( QFile::WriteOnly ) )
        {
          localPgServiceFile.write( psServiceFileContent.toUtf8() );
          localPgServiceFile.close();

          setenv( "PGSYSCONFDIR", systemLocalDataPath.toUtf8(), true );
        }
      }
      break;
    }
  }
#endif

#if WITH_SENTRY
  sentry_wrapper::install_message_handler();
#endif
  app.initQgis();
  app.setThemeName( settings.value( "/Themes", "default" ).toString() );
#ifdef RELATIVE_PREFIX_PATH
  app.setPkgDataPath( QfPlatformUtilities::instance()->systemSharedDataLocation() + QStringLiteral( "/qgis" ) );
#endif
  app.createDatabase();

  initAuthManager( QgsApplication::authManager() );

  if ( !qfieldFontName.isEmpty() )
  {
    QgsStyle *defaultStyle = QgsStyle::defaultStyle();
    QgsTextFormat textFormat = defaultStyle->defaultTextFormat();
    QFont font = textFormat.font();
    font.setFamily( qfieldFontName );
    textFormat.setFont( font );
    defaultStyle->addTextFormat( QStringLiteral( "Default" ), textFormat, true );
  }

  QSettings::setDefaultFormat( QSettings::NativeFormat );

  // Set up the QSettings environment must be done after qapp is created
  QCoreApplication::setOrganizationName( "OPENGIS.ch" );
  QCoreApplication::setOrganizationDomain( "opengis.ch" );
  QCoreApplication::setApplicationName( Qfield::appName );

  app.installTranslator( qtTranslator );
  app.installTranslator( qfieldTranslator );

  QLocale locale;
  const QString localeName = locale.name();
  const qsizetype localeTagSeparator = localeName.indexOf( QStringLiteral( "_" ) );
  QgsApplication::settingsLocaleUserLocale->setValue( localeName.mid( 0, localeTagSeparator ) );

  qputenv( "QT_QUICK_CONTROLS_STYLE", QByteArray( "Material" ) );
  qputenv( "QT_QUICK_CONTROLS_MATERIAL_VARIANT", QByteArray( "Dense" ) );

  QgisMobileapp mApp( &app );

#ifdef WITH_SPIX
  spix::AnyRpcServer server;
  auto bot = new spix::QtQmlBot();
  bot->runTestServer( server );
#endif

  return app.exec();
}
