import Foundation

/// Sacred texts quoted verbatim from their published sources.
///
/// Never edit these strings by hand. `SacredTextTests` checks each one against
/// the SHA-256 of the text as published at its source.
enum SacredText {
    /// Musnad Ahmad 6799, in Ahmad's wording (أحمد شاكر: إسناده صحيح).
    /// Source: https://dorar.net/hadith/sharh/116139
    static let reciteAndAscend = "يقالُ لصاحِبِ القرآنِ اقرَأ وارقَ ورتِّل كما كُنتَ ترتِّلُ في الدُّنيا فإنَّ منزلتَكَ عندَ آخرِ آيةٍ تقرؤُها"

    /// The companion who narrated `reciteAndAscend`, per https://dorar.net/hadith/sharh/116139
    static let reciteAndAscendNarrator = "عن عبد الله بن عمرو رضي الله عنهما"

    /// The phrase emphasized inside `reciteAndAscend`.
    static let reciteAndAscendEmphasis = "اقرَأ وارقَ"

    /// English translation of Jami' at-Tirmidhi 2914 (Darussalam), exactly as published.
    /// Source: https://sunnah.com/tirmidhi:2914
    static let reciteAndAscendTranslation = "\"It shall be said - meaning to the one who memorized the Qur'an - 'Recite, and rise up, recite (melodiously) as you would recite in the world. For indeed your rank shall be at the last Ayah you recited.'\""
}
