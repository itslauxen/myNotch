import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Chaves dos ajustes no UserDefaults (lidos com @AppStorage nas telas e direto aqui fora delas).
enum Config {
    static let limiteBandeja = "bandejaLimite"
    static let bandejaTextos = "bandejaTextos"
    static let bandejaImagens = "bandejaImagens"
    static let idiomaDitado = "ditadoIdioma"
    static let pararNoSilencio = "ditadoPararNoSilencio"
    static let fonteNota = "notaFonte"
    static let atalhoNotch = "atalhoNotch"
    static let atalhoDitado = "atalhoDitado"

    static let fontePadrao: Double = 13

    /// Integração com o Nova Notes (Ajustes › Geral). Desligada, a aba Nova e a conta somem.
    static let novaNotes = "novaNotes"
    static var novaLigada: Bool { bool(novaNotes, true) }

    static func int(_ chave: String, _ padrao: Int) -> Int {
        UserDefaults.standard.object(forKey: chave) as? Int ?? padrao
    }
    static func bool(_ chave: String, _ padrao: Bool) -> Bool {
        UserDefaults.standard.object(forKey: chave) as? Bool ?? padrao
    }
    static func texto(_ chave: String, _ padrao: String) -> String {
        UserDefaults.standard.string(forKey: chave) ?? padrao
    }
    static func double(_ chave: String, _ padrao: Double) -> Double {
        UserDefaults.standard.object(forKey: chave) as? Double ?? padrao
    }
}

/// Um atalho de teclado gravado nos Ajustes. Guardado como texto ("código;letra;modificadores")
/// para o @AppStorage aceitar.
struct Atalho: RawRepresentable, Equatable {
    var codigo: UInt16
    var letra: String
    var modificadores: NSEvent.ModifierFlags

    static let notchPadrao = Atalho(codigo: UInt16(kVK_ANSI_N), letra: "n", modificadores: [.command, .option])
    static let ditadoPadrao = Atalho(codigo: UInt16(kVK_ANSI_V), letra: "v", modificadores: [.command, .shift])

    init(codigo: UInt16, letra: String, modificadores: NSEvent.ModifierFlags) {
        self.codigo = codigo
        self.letra = letra
        self.modificadores = modificadores.intersection([.command, .option, .shift, .control])
    }

    init?(rawValue: String) {
        let partes = rawValue.split(separator: ";", omittingEmptySubsequences: false)
        guard partes.count == 3, let codigo = UInt16(partes[0]), let mods = UInt(partes[2]), !partes[1].isEmpty else { return nil }
        self.init(codigo: codigo, letra: String(partes[1]), modificadores: NSEvent.ModifierFlags(rawValue: mods))
    }

    var rawValue: String { "\(codigo);\(letra);\(modificadores.rawValue)" }

    static func ler(_ chave: String, _ padrao: Atalho) -> Atalho {
        UserDefaults.standard.string(forKey: chave).flatMap(Atalho.init(rawValue:)) ?? padrao
    }

    /// Como o macOS escreve nos menus: ⌃⌥⇧⌘ e a tecla.
    var texto: String {
        var s = ""
        if modificadores.contains(.control) { s += "⌃" }
        if modificadores.contains(.option) { s += "⌥" }
        if modificadores.contains(.shift) { s += "⇧" }
        if modificadores.contains(.command) { s += "⌘" }
        return s + letra.uppercased()
    }

    var carbon: UInt32 {
        var m = 0
        if modificadores.contains(.command) { m |= cmdKey }
        if modificadores.contains(.option) { m |= optionKey }
        if modificadores.contains(.shift) { m |= shiftKey }
        if modificadores.contains(.control) { m |= controlKey }
        return UInt32(m)
    }

    var swiftUI: SwiftUI.EventModifiers {
        var m: SwiftUI.EventModifiers = []
        if modificadores.contains(.command) { m.insert(.command) }
        if modificadores.contains(.option) { m.insert(.option) }
        if modificadores.contains(.shift) { m.insert(.shift) }
        if modificadores.contains(.control) { m.insert(.control) }
        return m
    }

    var tecla: KeyEquivalent { KeyEquivalent(Character(letra)) }
}

extension Notification.Name {
    /// Enquanto um atalho é gravado, o atalho global sai do ar (senão apertar ⌥⌘N esconderia o notch).
    static let gravandoAtalho = Notification.Name("myNotchGravandoAtalho")
}
