import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 4.16.0 — CLÉ D'ENVOI (Google Play, piste « Test interne »). Lue, dans cet ordre, dans les variables
// d'environnement (CI : secrets GitHub, voir .github/workflows/play.yml) puis dans android/key.properties (poste du
// développeur ; fichier JAMAIS commité, ignoré par android/.gitignore) :
//   ANDROID_KEYSTORE_PATH     / storeFile      chemin du fichier .jks (relatif à android/app ou absolu)
//   ANDROID_KEYSTORE_PASSWORD / storePassword  mot de passe du fichier
//   ANDROID_KEY_ALIAS         / keyAlias       alias de la clé
//   ANDROID_KEY_PASSWORD      / keyPassword    mot de passe de la clé
// Si l'un manque (ou si le fichier n'existe pas) : signature avec la clé DEBUG, comme avant la 4.16.0 (APK Sunmi
// construits sur le PC du pharmacien, APK de la CI : même signature qu'avant), avec un avertissement dans le journal ;
// Google Play refuse un tel paquet.
val proprietesCle = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}

fun reglageCle(variable: String, propriete: String): String? =
    System.getenv(variable)?.takeIf { it.isNotBlank() } ?: proprietesCle.getProperty(propriete)?.takeIf { it.isNotBlank() }

val cheminCle = reglageCle("ANDROID_KEYSTORE_PATH", "storeFile")
val motDePasseFichierCle = reglageCle("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val aliasCle = reglageCle("ANDROID_KEY_ALIAS", "keyAlias")
val motDePasseCle = reglageCle("ANDROID_KEY_PASSWORD", "keyPassword")

// 4.16.0 — API CIBLE. Google Play exige targetSdk 36 (Android 16) depuis le 31/08/2026 ; Flutter 3.32.8 propose 35.
// Le build Google Play (play.yml : flutter build appbundle -P prestinvTargetSdk=36) passe à 36 ; les APK construits
// sur le PC du pharmacien (terminaux Sunmi) et par ci.yml gardent la valeur de Flutter (35) : comportements d'Android
// 16 (retour prédictif, bord à bord imposé, orientation sur grand écran) inchangés pour eux, et aucune plateforme
// « Android 16 » à installer sur le poste (docs/android/README.md, docs/NOTE_VERSION_4.16.0.md).
val apiCiblePlay: Int? = (findProperty("prestinvTargetSdk") as String?)?.trim()?.toIntOrNull()

android {
    namespace = "com.dici.prestinv"
    compileSdk = apiCiblePlay ?: flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    ndkVersion = "27.0.12077973" // Ajoutez ou modifiez cette ligne

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dici.prestinv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = apiCiblePlay ?: flutter.targetSdkVersion
        // Version unique : celle de pubspec.yaml (« version: X.Y.Z+N » → versionName X.Y.Z, versionCode N).
        // Aucun numéro en dur ici (test/non_regression/version_sunmi_test.dart, docs/VERSIONS_SUNMI.md).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Ajouter ce bloc pour renommer les fichiers de sortie
    applicationVariants.all {
        val variant = this // 'this' fait référence à la variante (ex: release, debug)
        outputs.all {
            // 'this' ici fait référence à la sortie (l'APK)
            // Nous changeons le nom du fichier de sortie.
            val outputImpl = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            // Construire le nouveau nom, par exemple : prestigeinv-release-1.0.0+1.apk
            outputImpl.outputFileName = "prestigeinv-${variant.name}-${variant.versionName}.apk"
        }
    }

    // Relevé par play.yml (contrôle du build Google Play).
    logger.lifecycle("Prestige Inventaire : targetSdk ${apiCiblePlay ?: flutter.targetSdkVersion}")

    val fichierCle = cheminCle?.let { file(it) }
    val cleEnvoiComplete = fichierCle != null && fichierCle.exists() &&
        motDePasseFichierCle != null && aliasCle != null && motDePasseCle != null

    signingConfigs {
        if (cleEnvoiComplete) {
            create("release") {
                storeFile = fichierCle
                storePassword = motDePasseFichierCle
                keyAlias = aliasCle
                keyPassword = motDePasseCle
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (cleEnvoiComplete) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "Prestige Inventaire : clé d'envoi absente ou incomplète (ANDROID_KEYSTORE_* / android/key.properties) " +
                        "— paquet release signé avec la clé DEBUG (APK Sunmi et essais ; refusé par Google Play)."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}
dependencies {
    implementation(project(":integration_test"))
}

flutter {
    source = "../.."
}
