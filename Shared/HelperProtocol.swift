//
//  HelperProtocol.swift
//  CleanMyOwnShared
//
//  Contrato XPC entre la app y el helper privilegiado (SMAppService.daemon).
//
//  Deliberadamente ESTRECHO: no existe un verbo "ejecuta este comando como
//  root". Cada operación es concreta, validable y acotada — si un proceso
//  hostil llegara a hablar con el helper, lo máximo que puede pedir es lo
//  mismo que la app ofrece, dentro de la misma allowlist.
//

import Foundation

public enum HelperConstants {
    /// Nombre del mach service (coincide con MachServices en el plist del daemon).
    public static let machServiceName = "com.matos.CleanMyOwn.helper"
    /// Nombre del plist dentro de Contents/Library/LaunchDaemons.
    public static let plistName = "com.matos.CleanMyOwn.helper.plist"
    /// Versión del protocolo — la app la verifica al conectar. Si el daemon
    /// instalado responde con una versión menor, la app lo marca como
    /// desactualizado (UI ofrece Reinstalar) y cae a AEWP.
    /// v2: añade flushDNSCache y reindexSpotlight (módulo Mantenimiento).
    public static let version = 2
    /// Requirement de firma exigido al cliente cuando NO hay equipo (firma
    /// ad-hoc): sólo se puede anclar el identifier. Ver README para los
    /// límites de esta validación y por qué los verbos estrechos + allowlist
    /// son la defensa principal en ese modo.
    public static let clientCodeSigningRequirement = #"identifier "com.matos.CleanMyOwn""#

    /// Requirement del cliente según cómo esté firmado el helper. Con un
    /// equipo real (Apple Development / Developer ID) exige cadena de Apple +
    /// identifier + MISMO Team ID — un binario ad-hoc ya no puede suplantarlo.
    public static func clientRequirement(teamID: String?) -> String {
        guard let teamID, !teamID.isEmpty else {
            return clientCodeSigningRequirement
        }
        return #"anchor apple generic and identifier "com.matos.CleanMyOwn" and certificate leaf[subject.OU] = ""# + teamID + #"""#
    }
}

/// Verbos expuestos por el helper. Las replies devuelven (exitCode, output).
@objc public protocol HelperXPCProtocol {
    func version(reply: @escaping (Int) -> Void)
    /// Borra paths con `/bin/rm -rf --` tras validarlos contra
    /// `RootRemovalPolicy` usando el HOME derivado del euid del CLIENTE
    /// (nunca un home que el cliente declare).
    func removeItems(paths: [String], reply: @escaping (Int32, String) -> Void)
    /// `tmutil deletelocalsnapshots <date>` con formato validado.
    func deleteTimeMachineSnapshot(date: String, reply: @escaping (Int32, String) -> Void)
    /// `/usr/sbin/purge`.
    func purgeMemory(reply: @escaping (Int32, String) -> Void)
    /// Vacía la caché de DNS (`dscacheutil -flushcache` + HUP a mDNSResponder).
    func flushDNSCache(reply: @escaping (Int32, String) -> Void)
    /// Reindexa Spotlight en el volumen raíz (`mdutil -E /`).
    func reindexSpotlight(reply: @escaping (Int32, String) -> Void)
}

public enum HelperValidation {
    /// Identificador de snapshot de tmutil: `YYYY-MM-DD-HHMMSS`.
    public static func isValidSnapshotDate(_ s: String) -> Bool {
        s.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$", options: .regularExpression) != nil
    }
}
