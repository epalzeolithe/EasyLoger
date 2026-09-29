import SwiftUI
import Foundation
import CloudKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import MapKit
import Observation
import UniformTypeIdentifiers
import WebKit

struct PropertyListing: Identifiable, Codable, Hashable {
    var id: UUID
    var addedAt: Date? = nil
    var additionIndex: Int? = nil
    var sourceURL: URL
    var title: String
    var agencyName: String?
    var contactPhone: String? = nil
    var isContactNameManuallyEdited: Bool? = nil
    var isContactPhoneManuallyEdited: Bool? = nil
    var neighborhood: String
    var city: String
    var preciseLocation: String? = nil
    var price: Int
    var surface: Double
    var rooms: Int
    var bedrooms: Int
    var publishedAt: Date
    var visitDate: Date? = nil
    var summary: String
    var analysis: String
    var notes: String
    var imageURLs: [URL]
    var latitude: Double
    var longitude: Double
    var status: ListingStatus

    var pricePerSquareMeter: Int {
        guard surface > 0 else { return 0 }
        return Int(Double(price) / surface)
    }

    var hasExternalSource: Bool {
        guard let scheme = sourceURL.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static let sample = PropertyListing(
        id: UUID(),
        sourceURL: URL(string: "https://www.seloger.com/annonces/achat/appartement/montpellier-34/")!,
        title: "Appartement lumineux avec terrasse",
        agencyName: nil,
        neighborhood: "Boutonnet",
        city: "Montpellier",
        price: 329_000,
        surface: 68,
        rooms: 3,
        bedrooms: 2,
        publishedAt: .now.addingTimeInterval(-172_800),
        summary: "Bon candidat : deux chambres, extérieur et emplacement calme. Le prix au m² est à comparer aux ventes récentes du quartier.",
        analysis: "Le plan semble fonctionnel et la terrasse est un vrai atout. Les photos ne montrent pas de rénovation lourde. À vérifier : DPE complet, montant des charges, taxe foncière, procès-verbaux de copropriété et éventuels travaux votés.",
        notes: "",
        imageURLs: [
            URL(string: "https://images.unsplash.com/photo-1522708323590-d24dbb6b0267d?auto=format&fit=crop&w=1200&q=80")!,
            URL(string: "https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?auto=format&fit=crop&w=1200&q=80")!
        ],
        latitude: 43.6223,
        longitude: 3.8687,
        status: .new
    )
}

enum ListingStatusColor: String, Codable, CaseIterable, Identifiable {
    case accent
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case blue
    case indigo
    case purple
    case pink
    case gray

    var id: Self { self }

    var title: String {
        switch self {
        case .accent: "Accent"
        case .red: "Rouge"
        case .orange: "Orange"
        case .yellow: "Jaune"
        case .green: "Vert"
        case .mint: "Menthe"
        case .teal: "Sarcelle"
        case .cyan: "Cyan"
        case .blue: "Bleu"
        case .indigo: "Indigo"
        case .purple: "Violet"
        case .pink: "Rose"
        case .gray: "Gris"
        }
    }

    var color: Color {
        switch self {
        case .accent: .accentColor
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}

struct ListingStatus: RawRepresentable, Codable, Hashable, Identifiable {
    let rawValue: String
    let colorChoice: ListingStatusColor

    var id: String { rawValue }
    var color: Color { colorChoice.color }

    static let new = Self(rawValue: "Nouveau", colorChoice: .orange)
    static let toContact = Self(rawValue: "À contacter", colorChoice: .green)
    static let contactEstablished = Self(rawValue: "Contact établi", colorChoice: .cyan)
    static let visitToSchedule = Self(rawValue: "Visite à programmer", colorChoice: .blue)
    static let visitScheduled = Self(rawValue: "Visite programmée", colorChoice: .indigo)
    static let visited = Self(rawValue: "Visité", colorChoice: .green)
    static let revisit = Self(rawValue: "À revisiter", colorChoice: .purple)
    static let standby = Self(rawValue: "Stand by", colorChoice: .gray)
    static let rejected = Self(rawValue: "Écarté", colorChoice: .gray)

    static let defaultOrder: [Self] = [
        .visitScheduled,
        .visitToSchedule,
        .revisit,
        .visited,
        .contactEstablished,
        .toContact,
        .new,
        .standby,
        .rejected
    ]

    init(rawValue: String) {
        self.init(rawValue: rawValue, colorChoice: .accent)
    }

    init(rawValue: String, colorChoice: ListingStatusColor) {
        self.rawValue = rawValue
        self.colorChoice = colorChoice
    }

    private enum CodingKeys: String, CodingKey {
        case rawValue
        case colorChoice
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let value = try? container.decode(String.self, forKey: .rawValue) {
            rawValue = value
            colorChoice = try container.decodeIfPresent(ListingStatusColor.self, forKey: .colorChoice) ?? .accent
            return
        }

        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "À étudier":
            self = .new
        case "Contact demandé", "Demande de contact envoyé":
            self = .toContact
        case "Contacté":
            self = .contactEstablished
        case "Visite":
            self = .visitScheduled
        default:
            self = Self(rawValue: value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
        try container.encode(colorChoice, forKey: .colorChoice)
    }
}

private struct EasySelogerBackup: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let listings: [PropertyListing]
    let favoriteIDs: [UUID]
    let statuses: [ListingStatus]?
}

private enum CloudSyncService {
    private static let recordType = "SharedAppData"
    private static let recordID = CKRecord.ID(recordName: "shared-easyseloger-data")
    private static let payloadKey = "payload"
    private static let subscriptionID = "shared-app-data-changes"
    private static let database = CKContainer.default().publicCloudDatabase

    static func ensureChangeSubscription() async throws {
        do {
            _ = try await database.subscription(for: subscriptionID)
            return
        } catch let error as CKError where error.code == .unknownItem {
            let subscription = CKQuerySubscription(
                recordType: recordType,
                predicate: NSPredicate(value: true),
                subscriptionID: subscriptionID,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate]
            )
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo
            _ = try await database.save(subscription)
        }
    }

    static func fetchBackup() async throws -> EasySelogerBackup? {
        do {
            let record = try await database.record(for: recordID)
            guard let data = record[payloadKey] as? Data else {
                return nil
            }
            return try JSONDecoder().decode(EasySelogerBackup.self, from: data)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    static func saveMerging(_ localBackup: EasySelogerBackup) async throws -> EasySelogerBackup {
        for attempt in 0..<3 {
            let record: CKRecord
            let cloudBackup: EasySelogerBackup?
            let fetchedRecord: CKRecord?

            do {
                fetchedRecord = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                fetchedRecord = nil
            }

            if let fetchedRecord {
                record = fetchedRecord
                if let data = record[payloadKey] as? Data {
                    cloudBackup = try JSONDecoder().decode(EasySelogerBackup.self, from: data)
                } else {
                    cloudBackup = nil
                }
            } else {
                record = CKRecord(recordType: recordType, recordID: recordID)
                cloudBackup = nil
            }

            var mergedListings = cloudBackup?.listings ?? []
            for localListing in localBackup.listings {
                if let index = mergedListings.firstIndex(where: {
                    $0.id == localListing.id
                        || $0.sourceURL.path == localListing.sourceURL.path
                }) {
                    mergedListings[index] = localListing
                } else {
                    mergedListings.append(localListing)
                }
            }

            let mergedListingIDs = Set(mergedListings.map(\.id))
            let mergedFavoriteIDs = Set(cloudBackup?.favoriteIDs ?? [])
                .union(localBackup.favoriteIDs)
                .intersection(mergedListingIDs)
            var mergedStatuses = cloudBackup?.statuses ?? []
            for localStatus in localBackup.statuses ?? [] {
                if let index = mergedStatuses.firstIndex(where: {
                    $0.rawValue == localStatus.rawValue
                }) {
                    mergedStatuses[index] = localStatus
                } else {
                    mergedStatuses.append(localStatus)
                }
            }

            let mergedBackup = EasySelogerBackup(
                formatVersion: EasySelogerBackup.currentFormatVersion,
                exportedAt: .now,
                listings: mergedListings,
                favoriteIDs: mergedFavoriteIDs.sorted { $0.uuidString < $1.uuidString },
                statuses: mergedStatuses
            )
            record[payloadKey] = try JSONEncoder().encode(mergedBackup) as CKRecordValue
            record["updatedAt"] = mergedBackup.exportedAt as CKRecordValue

            do {
                _ = try await database.save(record)
                return mergedBackup
            } catch let error as CKError
            where error.code == .serverRecordChanged && attempt < 2 {
                continue
            }
        }

        throw CKError(.serverRecordChanged)
    }
}

private enum BackupError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        "Ce fichier n’est pas une sauvegarde EasySeloger compatible."
    }
}

@MainActor
private final class EasySelogerBackupDocument: WritableDocument {
    static let writableContentTypes: [UTType] = [.json]

    private let data: Data

    init(data: Data) {
        self.data = data
    }

    nonisolated func writer(
        configuration: sending WriteConfiguration
    ) -> sending FileWrapperDocumentWriter<Data> {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            FileWrapper(regularFileWithContents: snapshot)
        }
    }

    func snapshot(contentType: UTType) async throws -> sending Data {
        data
    }
}

private enum ListingImportError: LocalizedError {
    case pageUnavailable
    case incompleteListing

    var errorDescription: String? {
        switch self {
        case .pageUnavailable:
            "SeLoger n’a pas permis de charger cette annonce. Réessayez après avoir ouvert le lien dans Safari."
        case .incompleteListing:
            "L’annonce a été chargée, mais son prix ou sa surface n’a pas pu être identifié. Aucun faux bien n’a été ajouté."
        }
    }
}

private struct ImportedListingData: Decodable {
    var title: String?
    var description: String?
    var agencyName: String?
    var contactPhone: String?
    var price: Double?
    var surface: Double?
    var rooms: Int?
    var bedrooms: Int?
    var address: String?
    var images: [String]
    var pageText: String
}

@MainActor
private enum SeLogerImporter {
    static func configuredPage() -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.defaultNavigationPreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        let page = WebPage(configuration: configuration)
        page.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        return page
    }

    static func importListing(from url: URL, page suppliedPage: WebPage? = nil) async throws -> PropertyListing {
        let page: WebPage
        if let suppliedPage {
            page = suppliedPage
        } else {
            let createdPage = configuredPage()
            do {
                for try await _ in createdPage.load(URLRequest(url: url)) {}
            } catch {
                throw ListingImportError.pageUnavailable
            }
            page = createdPage
        }

        let script = """
        const firstValue = (object, keys) => {
            if (!object || typeof object !== "object") return null;
            for (const key of keys) {
                if (object[key] !== undefined && object[key] !== null) {
                    const value = object[key];
                    if (typeof value === "object" && value.value !== undefined) return value.value;
                    return value;
                }
            }
            for (const value of Object.values(object)) {
                const found = firstValue(value, keys);
                if (found !== null) return found;
            }
            return null;
        };

        const structured = [];
        document.querySelectorAll('script[type="application/ld+json"]').forEach(script => {
            try { structured.push(JSON.parse(script.textContent)); } catch (_) {}
        });

        const sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

        const revealedPhoneCandidates = [];
        const revealPhoneNumber = async () => {
            const revealButton = Array.from(document.querySelectorAll("button, a")).find(element => {
                const label = [
                    element.innerText,
                    element.getAttribute("aria-label"),
                    element.getAttribute("title")
                ].filter(Boolean).join(" ");
                return /afficher (?:le )?numéro|voir (?:le )?numéro/i.test(label);
            });
            if (revealButton) {
                const linksBeforeReveal = new Set(
                    Array.from(document.querySelectorAll('a[href^="tel:"]'))
                        .map(link => link.getAttribute("href"))
                );
                revealButton.click();
                await sleep(500);

                Array.from(document.querySelectorAll('a[href^="tel:"]'))
                    .map(link => link.getAttribute("href"))
                    .filter(href => href && !linksBeforeReveal.has(href))
                    .forEach(href => revealedPhoneCandidates.push(href));

                let container = revealButton.parentElement;
                for (let depth = 0; container && depth < 6; depth += 1) {
                    revealedPhoneCandidates.push(container.innerText || "");
                    container = container.parentElement;
                }
            }
        };

        const originalScrollY = window.scrollY;
        const pageTextSnapshots = [document.body?.innerText || ""];
        for (const ratio of [0.25, 0.5, 0.75, 1]) {
            window.scrollTo(0, document.documentElement.scrollHeight * ratio);
            await sleep(350);
            await revealPhoneNumber();
            pageTextSnapshots.push(document.body?.innerText || "");
        }
        window.scrollTo(0, originalScrollY);
        await sleep(250);
        const listingPageText = pageTextSnapshots.join("\\n");

        const photoLauncher = Array.from(document.querySelectorAll("button, a")).find(element => {
            const text = (element.innerText || element.getAttribute("aria-label") || "").trim();
            return /(?:afficher|voir|toutes?)[^\\n]{0,20}photos?/i.test(text);
        });
        if (photoLauncher) {
            photoLauncher.click();
            await sleep(700);
        }

        for (let index = 0; index < 40; index += 1) {
            const nextButton = Array.from(document.querySelectorAll("button")).find(button => {
                const label = [
                    button.getAttribute("aria-label"),
                    button.getAttribute("title"),
                    button.innerText
                ].filter(Boolean).join(" ");
                return /suivant|next|photo suivante/i.test(label) && !button.disabled;
            });
            if (!nextButton) break;
            nextButton.click();
            await sleep(90);
        }

        const closeGalleryButton = Array.from(document.querySelectorAll(
            '[role="dialog"] button, [aria-modal="true"] button'
        )).find(button => {
            const label = [
                button.getAttribute("aria-label"),
                button.getAttribute("title"),
                button.innerText
            ].filter(Boolean).join(" ");
            return /fermer|close/i.test(label);
        });
        closeGalleryButton?.click();
        await sleep(250);

        const normalizeImages = values => values.flatMap(value => {
            if (typeof value === "string") return [value];
            if (value && typeof value === "object") return [value.url || value.contentUrl];
            return [];
        });

        const structuredImages = normalizeImages(structured.flatMap(item => {
            const value = firstValue(item, ["image", "images", "photos"]);
            return Array.isArray(value) ? value : (value ? [value] : []);
        }));

        const gallerySelectors = [
            '[class*="gallery"] img',
            '[class*="Gallery"] img',
            '[class*="carousel"] img',
            '[class*="Carousel"] img',
            '[class*="swiper"] img',
            '[role="dialog"] img',
            '[data-testid*="gallery"] img',
            '[data-testid*="media"] img',
            '[data-testid*="photo"] img'
        ].join(",");

        const urlsFromImage = image => {
            const values = [
                image.currentSrc,
                image.src,
                image.getAttribute("data-src"),
                image.getAttribute("data-lazy-src"),
                image.getAttribute("data-original")
            ];
            const srcset = image.getAttribute("srcset") || image.getAttribute("data-srcset");
            if (srcset) {
                values.push(...srcset.split(",").map(item => item.trim().split(/\\s+/)[0]));
            }
            return values.filter(Boolean);
        };

        const galleryImages = Array.from(document.querySelectorAll(gallerySelectors))
            .flatMap(urlsFromImage);

        const largeTopImages = Array.from(document.images)
            .filter(image => {
                const rect = image.getBoundingClientRect();
                const isLarge = image.naturalWidth >= 600 && image.naturalHeight >= 350;
                return isLarge && rect.top < 1600;
            })
            .flatMap(urlsFromImage);

        const rawImages = [
            ...structuredImages,
            ...galleryImages,
            document.querySelector('meta[property="og:image"]')?.content,
            ...largeTopImages
        ];

        const rejectedImageTerms = [
            "logo", "avatar", "icon", "map", "maps", "streetview",
            "street-view", "travel", "route", "address", "pin", "marker",
            "agency", "agent", "georisque", "sprite"
        ];

        const canonicalURL = value => {
            try {
                const parsed = new URL(value);
                ["w", "width", "h", "height", "quality", "q"].forEach(key => parsed.searchParams.delete(key));
                return parsed.toString();
            } catch (_) {
                return value;
            }
        };

        const seen = new Set();
        const images = rawImages
            .filter(value => {
                if (typeof value !== "string" || !value.startsWith("http")) return false;
                const lowercased = value.toLowerCase();
                if (lowercased.endsWith(".svg") ||
                    rejectedImageTerms.some(term => lowercased.includes(term))) return false;
                const canonical = canonicalURL(value);
                if (seen.has(canonical)) return false;
                seen.add(canonical);
                return true;
            })
            .slice(0, 60);

        const bodyText = [
            listingPageText,
            document.body?.innerText || ""
        ].filter(Boolean).join("\\n");
        const numeric = value => {
            if (typeof value === "number") return value;
            if (typeof value !== "string") return null;
            const parsed = Number(value.replace(/[^0-9,.]/g, "").replace(",", "."));
            return Number.isFinite(parsed) ? parsed : null;
        };

        const title = document.querySelector("h1")?.innerText ||
            document.querySelector('meta[property="og:title"]')?.content ||
            document.title;
        const description = document.querySelector('meta[property="og:description"]')?.content ||
            document.querySelector('meta[name="description"]')?.content;

        const embeddedData = [...structured];
        document.querySelectorAll('script[id="__NEXT_DATA__"], script[type="application/json"]').forEach(script => {
            try { embeddedData.push(JSON.parse(script.textContent)); } catch (_) {}
        });

        const nameFromObject = value => {
            if (!value || typeof value !== "object") return null;
            const fullName = [
                value.firstName || value.firstname || value.givenName,
                value.lastName || value.lastname || value.familyName
            ].filter(Boolean).join(" ").trim();
            return fullName || value.fullName || value.contactName ||
                value.displayName || value.name || null;
        };

        const contactKeys = [
            "contactName", "agentName", "negotiatorName", "advisorName",
            "consultantName", "representativeName", "salespersonName"
        ];
        let contactName = firstValue(embeddedData, contactKeys);
        if (typeof contactName !== "string") {
            const contactObject = firstValue(embeddedData, [
                "contact", "agent", "negotiator", "advisor", "consultant",
                "representative", "salesperson"
            ]);
            contactName = typeof contactObject === "string"
                ? contactObject
                : nameFromObject(contactObject);
        }

        const bodyLines = bodyText
            .split("\\n")
            .map(value => value.trim())
            .filter(Boolean);

        const ignoredContactLine = value =>
            /votre contact|contactez|contacter|conseiller immobilier|agent commercial|mandataire|téléphone|afficher|envoyer un message|appeler|voir le numéro|site internet|référence|honoraires|informations légales/i.test(value);

        const isLikelyPersonName = value =>
            value.length > 2 &&
            value.length < 80 &&
            !ignoredContactLine(value) &&
            !/[€@]|https?:|\\d{3,}/i.test(value) &&
            /^[\\p{L}][\\p{L}'’ .-]+$/u.test(value);

        const agencyHeadingIndex = bodyLines.findIndex(value =>
            /découvrez l.agence/i.test(value)
        );
        const contactHeadingIndex = bodyLines.findIndex((value, index) =>
            index > agencyHeadingIndex && /votre contact/i.test(value)
        );

        const isLikelyAgencyName = value =>
            value.length > 2 &&
            value.length < 100 &&
            !/^(agence|informations légales|profil)$/i.test(value) &&
            !/^(siège|rcs|siret)\\s*:/i.test(value) &&
            !/avenue|boulevard|rue|route|chemin|place/i.test(value) &&
            !/[€@]|https?:|[0-9]{5}/i.test(value);

        const agencyNameFromHeading = agencyHeadingIndex >= 0
            ? bodyLines
                .slice(agencyHeadingIndex + 1, agencyHeadingIndex + 10)
                .find(isLikelyAgencyName) || null
            : null;

        const agencySectionEnd = contactHeadingIndex > agencyHeadingIndex
            ? contactHeadingIndex + 12
            : agencyHeadingIndex + 30;
        const agencySectionText = agencyHeadingIndex >= 0
            ? bodyLines.slice(agencyHeadingIndex, agencySectionEnd).join(" ")
            : "";
        const phonePattern = /(?:^|[^0-9])((?:[+]33|0)[ .()-]*[1-9](?:[ .()-]*[0-9]{2}){4})(?![0-9])/;
        const normalizeFrenchPhone = value => {
            if (value === undefined || value === null) return null;
            const match = String(value).replace(/^tel:/i, "").match(phonePattern);
            if (!match) return null;

            const normalized = match[1].replace(/[^+0-9]/g, "");
            const nationalDigits = normalized.startsWith("+33")
                ? "0" + normalized.slice(3)
                : normalized;
            return nationalDigits.length === 10 ? normalized : null;
        };

        const phoneFromReveal = revealedPhoneCandidates
            .map(normalizeFrenchPhone)
            .find(Boolean);
        const phoneFromAgencySection = normalizeFrenchPhone(agencySectionText);
        const phoneFromScopedLink = Array.from(document.querySelectorAll('a[href^="tel:"]'))
            .find(link => {
                let container = link.parentElement;
                for (let depth = 0; container && depth < 6; depth += 1) {
                    const text = container.innerText || "";
                    if (/découvrez l.agence|votre contact/i.test(text) ||
                        (agencyNameFromHeading && text.includes(agencyNameFromHeading))) {
                        return true;
                    }
                    container = container.parentElement;
                }
                return false;
            });
        const structuredPhone = firstValue(embeddedData, [
            "telephone", "phone", "phoneNumber", "mobile", "mobilePhone"
        ]);
        const contactPhone = phoneFromReveal ||
            phoneFromAgencySection ||
            normalizeFrenchPhone(phoneFromScopedLink?.getAttribute("href")) ||
            normalizeFrenchPhone(structuredPhone) ||
            null;

        if (!contactName) {
            const contactSelectors = [
                '[data-testid*="contact"]',
                '[data-testid*="agent"]',
                '[data-testid*="advisor"]',
                '[data-testid*="negotiator"]',
                '[class*="contact"]',
                '[class*="Contact"]',
                '[class*="agent"]',
                '[class*="Agent"]',
                '[itemprop="employee"]',
                '[itemprop="agent"]'
            ].join(",");
            const contactLines = Array.from(document.querySelectorAll(contactSelectors))
                .flatMap(element => [
                    element.getAttribute("content"),
                    element.getAttribute("aria-label"),
                    ...(element.innerText || "").split("\\n")
                ])
                .filter(Boolean)
                .map(value => value.trim());
            contactName = contactLines.find(isLikelyPersonName) || null;
        }

        if (!contactName) {
            const contactHeadingIndex = bodyLines.findIndex(value =>
                /votre contact|contactez (?:notre |votre )?(?:conseiller|agent)|conseiller qui propose|agent qui propose/i.test(value)
            );
            if (contactHeadingIndex >= 0) {
                contactName = bodyLines
                    .slice(contactHeadingIndex + 1, contactHeadingIndex + 10)
                    .find(isLikelyPersonName) || null;
            }
        }

        const agencyKeys = [
            "agencyName", "advertiserName", "professionalName", "companyName",
            "accountName", "sellerName", "customerName", "brandName"
        ];
        let agencyName = firstValue(embeddedData, agencyKeys);

        if (typeof agencyName !== "string") {
            const agencyObject = firstValue(embeddedData, ["seller", "provider", "broker", "advertiser"]);
            agencyName = typeof agencyObject === "string"
                ? agencyObject
                : nameFromObject(agencyObject);
        }

        if (!agencyName) {
            const agencySelectors = [
                '[data-testid*="agency"]',
                '[data-testid*="advertiser"]',
                '[data-testid*="professional"]',
                '[class*="agency"]',
                '[class*="Agency"]',
                '[class*="advertiser"]',
                '[class*="professional"]'
            ].join(",");
            const agencyLines = Array.from(document.querySelectorAll(agencySelectors))
                .flatMap(element => (element.innerText || "").split("\\n"))
                .map(value => value.trim())
                .filter(value => value.length > 2 && value.length < 100);
            agencyName = agencyLines.find(value =>
                !/découvrez l.agence|proposé par|contacter|téléphone|afficher|envoyer un message|appeler|voir le numéro|site internet/i.test(value)
            ) || null;
        }

        if (!agencyName) {
            const headingIndex = bodyLines.findIndex(value =>
                /découvrez l.agence|agence qui propose|professionnel qui propose/i.test(value)
            );
            if (headingIndex >= 0) {
                agencyName = bodyLines.slice(headingIndex + 1, headingIndex + 8).find(value =>
                    value.length < 100 &&
                    !/agence$|proposé par|contacter|envoyer|afficher|téléphone|adresse|appeler|voir le numéro/i.test(value)
                ) || null;
            }
        }

        if (!agencyName) {
            agencyName = bodyLines.find(value =>
                value.length < 80 &&
                /(?:immobilier|immobilière|\\bimmo\\b)/i.test(value) &&
                !/annonce|marché|projet|agence immobilière$|prix immobilier/i.test(value)
            ) || null;
        }

        if (!agencyName) {
            const agencyMatch = bodyText.match(/\\n([^\\n]{2,80})\\n(?:Agence|Proposé par une agence)/i);
            agencyName = agencyMatch ? agencyMatch[1].trim() : null;
        }

        agencyName = agencyNameFromHeading || agencyName || contactName;
        if (typeof agencyName === "string") {
            agencyName = agencyName
                .replace(/(immobilier|immobilière|\\bimmo)Agence$/i, "$1")
                .replace(/\\s+/g, " ")
                .trim();
        }

        let price = numeric(firstValue(structured, ["price", "lowPrice"]));
        let surface = numeric(firstValue(structured, ["floorSize", "surface", "livingArea"]));
        let rooms = numeric(firstValue(structured, ["numberOfRooms", "rooms"]));
        let bedrooms = numeric(firstValue(structured, ["numberOfBedrooms", "bedrooms"]));
        const addressValue = firstValue(structured, ["address", "name"]);

        if (!price) {
            const match = bodyText.match(/([0-9][0-9 \\u00a0\\u202f]{3,})[ ]*€/);
            price = match ? numeric(match[1]) : null;
        }
        if (!surface) {
            const match = bodyText.match(/([0-9]+(?:[,.][0-9]+)?)[ ]*m²/);
            surface = match ? numeric(match[1]) : null;
        }
        if (!rooms) {
            const match = bodyText.match(/([0-9]+)[ ]*pièces?/i);
            rooms = match ? numeric(match[1]) : null;
        }
        if (!bedrooms) {
            const match = bodyText.match(/([0-9]+)[ ]*chambres?/i);
            bedrooms = match ? numeric(match[1]) : null;
        }

        return JSON.stringify({
            title,
            description,
            agencyName,
            contactPhone,
            price,
            surface,
            rooms: rooms ? Math.round(rooms) : null,
            bedrooms: bedrooms ? Math.round(bedrooms) : null,
            address: typeof addressValue === "string" ? addressValue : null,
            images,
            pageText: bodyText.slice(0, 24000)
        });
        """

        guard let json = try? await page.callJavaScript(script, arguments: [:]) as? String,
              let data = json.data(using: .utf8),
              let imported = try? JSONDecoder().decode(ImportedListingData.self, from: data),
              let price = imported.price.map(Int.init),
              let surface = imported.surface,
              price > 0,
              surface > 0 else {
            throw ListingImportError.incompleteListing
        }

        let location = inferredLocation(from: imported)
        let title = cleanedTitle(imported.title)
        let imageURLs = imported.images.compactMap(URL.init(string:))
        let description = imported.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let analysisSource = description?.isEmpty == false ? description! : imported.pageText
        let report = detailedReport(
            imported: imported,
            price: price,
            surface: surface,
            location: location,
            source: analysisSource
        )

        return PropertyListing(
            id: UUID(),
            sourceURL: url,
            title: title,
            agencyName: cleanedAgencyName(imported.agencyName),
            contactPhone: imported.contactPhone,
            neighborhood: location.neighborhood,
            city: location.city,
            price: price,
            surface: surface,
            rooms: imported.rooms ?? 0,
            bedrooms: imported.bedrooms ?? 0,
            publishedAt: .now,
            summary: report.summary,
            analysis: report.analysis,
            notes: "",
            imageURLs: imageURLs,
            latitude: 43.6108,
            longitude: 3.8767,
            status: .new
        )
    }

    static func cleanedAgencyName(_ rawName: String?) -> String? {
        guard let rawName else { return nil }

        var cleaned = rawName
            .replacingOccurrences(of: "Proposé par une agence immobilière", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Agence immobilière", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lowercased = cleaned.lowercased()
        if lowercased.hasSuffix("agence"),
           lowercased.contains("immobilier") || lowercased.contains("immobilière") || lowercased.contains("immo") {
            cleaned = String(cleaned.dropLast("Agence".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let normalized = cleaned.lowercased()
        let rejectedValues = [
            "agence", "appeler", "contacter", "afficher le numéro",
            "envoyer un message", "voir le numéro", "site internet"
        ]

        guard !cleaned.isEmpty,
              cleaned.count <= 100,
              !rejectedValues.contains(normalized) else {
            return nil
        }
        return cleaned
    }

    static func cleanedTitle(_ rawTitle: String?) -> String {
        guard let rawTitle else { return "Appartement à vendre" }

        let lines = rawTitle
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let propertyTitle = lines.first(where: {
            let normalized = $0.lowercased()
            return !normalized.contains("€") &&
                (normalized.hasPrefix("appartement") ||
                 normalized.hasPrefix("maison") ||
                 normalized.hasPrefix("studio") ||
                 normalized.hasPrefix("loft"))
        }) {
            return propertyTitle
        }

        return lines.first(where: { !$0.contains("€") }) ?? "Appartement à vendre"
    }

    private static func detailedReport(
        imported: ImportedListingData,
        price: Int,
        surface: Double,
        location: (neighborhood: String, city: String),
        source: String
    ) -> (summary: String, analysis: String) {
        let pricePerSquareMeter = Int(Double(price) / surface)
        let cautiousLow = roundedPrice(Double(price) * 0.88)
        let cautiousHigh = roundedPrice(Double(price) * 0.94)
        let openingOffer = roundedPrice(Double(price) * 0.87)
        let notaryEstimate = roundedPrice(Double(price) * 1.08)
        let rooms = imported.rooms.map(String.init) ?? "non précisé"
        let bedrooms = imported.bedrooms.map(String.init) ?? "non précisé"
        let photoCount = imported.images.count
        let normalizedSource = source.lowercased()

        var strengths: [String] = []
        if imported.bedrooms ?? 0 >= 2 { strengths.append("Deux chambres ou plus : configuration recherchée et généralement liquide à la revente.") }
        if normalizedSource.contains("balcon") || normalizedSource.contains("terrasse") { strengths.append("Présence annoncée d’un extérieur.") }
        if normalizedSource.contains("rénov") { strengths.append("Le logement est présenté comme rénové ; les factures et garanties restent à contrôler.") }
        if normalizedSource.contains("cave") { strengths.append("Une cave est mentionnée dans l’annonce.") }
        if normalizedSource.contains("ascenseur") { strengths.append("Un ascenseur est mentionné dans l’annonce.") }
        if normalizedSource.contains("dpe c") || normalizedSource.contains("classe c") { strengths.append("Performance énergétique annoncée en classe C.") }
        if strengths.isEmpty { strengths.append("La typologie et l’emplacement méritent une visite, sous réserve de vérifier les informations manquantes.") }

        var vigilance = [
            "Montant exact des charges et détail des dépenses incluses.",
            "Taxe foncière et coût énergétique réel.",
            "Trois derniers procès-verbaux d’assemblée générale, fonds travaux, impayés et procédures.",
            "Travaux votés ou prévus sur toiture, façade, parties communes, réseaux et ascenseur.",
            "Plan coté, surfaces des pièces, vis-à-vis, bruit et luminosité aux différentes heures.",
            "Adresse précise, règlement de copropriété et diagnostics complets."
        ]
        if photoCount < 6 {
            vigilance.append("Seulement \(photoCount) photo(s) exploitable(s) : la distribution et l’état réel sont difficiles à juger.")
        }
        if !normalizedSource.contains("dpe") {
            vigilance.append("Classe DPE et valeurs détaillées non identifiées dans les données extraites.")
        }

        let summary = """
        Ce bien propose \(rooms) pièce(s), dont \(bedrooms) chambre(s), sur \(surface.formatted(.number.precision(.fractionLength(0...2)))) m² à \(location.neighborhood).
        Le prix affiché est de \(currency(price)), soit \(currency(pricePerSquareMeter))/m², à confronter aux ventes comparables du secteur.
        Point notable : \(strengths[0])
        Sous réserve de la visite et des documents de copropriété, une discussion entre \(currency(cautiousLow)) et \(currency(cautiousHigh)) paraît prudente, avec une première offre autour de \(currency(openingOffer)).
        """

        let facts = """
        • \(rooms) pièce(s), \(bedrooms) chambre(s)
        • Surface : \(surface.formatted(.number.precision(.fractionLength(0...2)))) m²
        • Prix : \(currency(price))
        • Prix affiché au m² : \(currency(pricePerSquareMeter))/m²
        • Secteur détecté : \(location.neighborhood), \(location.city)
        • Photos de l’appartement détectées : \(photoCount)
        • Budget indicatif avec 8 % de frais d’acquisition : \(currency(notaryEstimate))
        """

        let strengthsText = strengths.map { "• \($0)" }.joined(separator: "\n")
        let vigilanceText = vigilance.map { "• \($0)" }.joined(separator: "\n")

        let analysis = """
        VERDICT RAPIDE

        Le prix demandé est de \(currency(price)). La fourchette de \(currency(cautiousLow)) à \(currency(cautiousHigh)) ci-dessous est une base de négociation prudente, pas une estimation notariale. Elle doit être recalée avec l’adresse exacte, les ventes comparables récentes, l’état réel et les documents de copropriété.

        CE QUE PROPOSE L’ANNONCE

        \(facts)

        ANALYSE DU PRIX

        Le prix affiché ressort à \(currency(pricePerSquareMeter))/m². Trois scénarios de discussion :
        • \(currency(openingOffer)) : offre d’ouverture, justifiée par les inconnues restantes.
        • \(currency(cautiousLow)) à \(currency(cautiousHigh)) : zone de négociation prudente si la visite est convaincante.
        • \(currency(price)) : plein tarif, qui exige un état, un emplacement précis et une copropriété sans défaut notable.

        Aucune médiane notariale ou donnée de marché externe n’est incluse dans ce rapport local. Vérifiez le prix auprès de sources datées avant toute décision.

        POINTS FORTS

        \(strengthsText)

        POINTS DE VIGILANCE

        \(vigilanceText)

        SI C’EST POUR LOUER

        Le rendement ne peut pas être calculé sérieusement sans loyer de référence applicable à l’adresse, charges non récupérables, taxe foncière, assurance, vacance et fiscalité. Pour Montpellier, il faudra notamment vérifier l’encadrement des loyers et ne pas supposer qu’un complément de loyer est autorisé.

        RECOMMANDATION

        1. Obtenir l’adresse exacte, le plan, les diagnostics, les charges, la taxe foncière et les trois derniers PV d’AG.
        2. Vérifier les surfaces utiles, la lumière, le bruit, le vis-à-vis et la qualité réelle des éventuels extérieurs.
        3. Contrôler les factures et garanties si une rénovation est annoncée.
        4. Comparer avec des ventes récentes réellement comparables avant de fixer un plafond.
        5. Commencer la négociation autour de \(currency(openingOffer)) et ne relever l’offre qu’en fonction d’éléments vérifiables.
        """

        return (summary.trimmingCharacters(in: .whitespacesAndNewlines), analysis)
    }

    private static func roundedPrice(_ value: Double) -> Int {
        Int((value / 1_000).rounded() * 1_000)
    }

    private static func currency(_ value: Int) -> String {
        value.formatted(.currency(code: "EUR").precision(.fractionLength(0)))
    }

    private static func inferredLocation(from imported: ImportedListingData) -> (neighborhood: String, city: String) {
        let source = [imported.address, imported.description, imported.pageText]
            .compactMap { $0 }
            .joined(separator: "\n")

        let neighborhoods = ["Boutonnet", "Aiguelongue", "Antigone", "Écusson", "Beaux-Arts", "Port Marianne", "Hôpitaux-Facultés", "Croix d’Argent", "Prés d’Arènes"]
        let neighborhood = neighborhoods.first { source.localizedCaseInsensitiveContains($0) } ?? "Quartier non précisé"
        let city = source.localizedCaseInsensitiveContains("Montpellier") ? "Montpellier" : "Ville non précisée"
        return (neighborhood, city)
    }
}

fileprivate enum CloudSyncStatus {
    case idle
    case syncing
    case synced
    case failed

    var title: String {
        switch self {
        case .idle:
            "Synchronisation iCloud en attente"
        case .syncing:
            "Synchronisation iCloud en cours"
        case .synced:
            "Synchronisation iCloud à jour"
        case .failed:
            "Erreur de synchronisation iCloud"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            .secondary
        case .syncing:
            .orange
        case .synced:
            .green
        case .failed:
            .red
        }
    }
}

@MainActor
@Observable
final class PropertyStore {
    var listings: [PropertyListing] = []
    var favoriteIDs: Set<UUID> = []
    var statuses: [ListingStatus] = ListingStatus.defaultOrder
    var isImportingListing = false
    var errorMessage: String?
    var cloudSyncErrorMessage: String?
    fileprivate var cloudSyncStatus = CloudSyncStatus.idle

    private let listingsKey = "savedListings"
    private let favoritesKey = "favoriteListingIDs"
    private let statusesKey = "listingStatuses"
    private let nextListingIndexKey = "nextListingIndex"
    private let localModificationDateKey = "localModificationDate"
    @ObservationIgnored private var cloudUploadTask: Task<Void, Never>?
    @ObservationIgnored private var isApplyingCloudBackup = false
    @ObservationIgnored private var localModificationDate = Date.distantPast
    @ObservationIgnored private var localMutationGeneration = 0

    init() {
        isApplyingCloudBackup = true
        load()
        isApplyingCloudBackup = false
    }

    func refreshFromCloud() async {
        guard cloudSyncStatus != .syncing else { return }

        cloudSyncStatus = .syncing
        let mutationGenerationAtStart = localMutationGeneration
        do {
            async let subscription: Void = CloudSyncService.ensureChangeSubscription()
            async let cloudBackup = CloudSyncService.fetchBackup()

            if let backup = try await cloudBackup {
                if mutationGenerationAtStart != localMutationGeneration
                    || backup.exportedAt < localModificationDate {
                    try await uploadToCloud()
                } else {
                    let (mergedBackup, containsLocalOnlyData) = mergingLocalData(into: backup)
                    apply(mergedBackup)
                    localModificationDate = backup.exportedAt
                    UserDefaults.standard.set(backup.exportedAt, forKey: localModificationDateKey)
                    if containsLocalOnlyData {
                        try await uploadToCloud()
                    }
                }
            } else {
                try await uploadToCloud()
            }
            try await subscription
            cloudSyncStatus = .synced
            cloudSyncErrorMessage = nil
        } catch is CancellationError {
            return
        } catch let error as CKError where error.code == .operationCancelled {
            return
        } catch {
            cloudSyncStatus = .failed
            cloudSyncErrorMessage = "Synchronisation iCloud impossible : \(error.localizedDescription)"
        }
    }

    @discardableResult
    func addListing(from url: URL, page: WebPage? = nil) async -> Bool {
        guard url.host?.contains("seloger.com") == true else {
            errorMessage = "Veuillez saisir une URL directe provenant de seloger.com."
            return false
        }

        isImportingListing = true
        defer { isImportingListing = false }

        do {
            var listing = try await SeLogerImporter.importListing(from: url, page: page)

            if let existingIndex = listings.firstIndex(where: { $0.sourceURL.path == url.path }) {
                let existingListing = listings[existingIndex]
                var replacement = listing
                replacement.id = existingListing.id
                replacement.addedAt = existingListing.addedAt ?? .now
                replacement.additionIndex = existingListing.additionIndex
                replacement.notes = existingListing.notes
                replacement.status = existingListing.status
                replacement.preciseLocation = existingListing.preciseLocation
                replacement.isContactNameManuallyEdited = existingListing.isContactNameManuallyEdited
                replacement.isContactPhoneManuallyEdited = existingListing.isContactPhoneManuallyEdited

                if existingListing.isContactNameManuallyEdited == true {
                    replacement.agencyName = existingListing.agencyName
                }
                if existingListing.isContactPhoneManuallyEdited == true {
                    replacement.contactPhone = existingListing.contactPhone
                }

                listings[existingIndex] = replacement
            } else {
                listing.addedAt = .now
                listing.additionIndex = allocateListingIndex()
                listings.insert(listing, at: 0)
            }
            save()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addManualListing(_ listing: PropertyListing) {
        var newListing = listing
        newListing.addedAt = newListing.addedAt ?? .now
        newListing.additionIndex = allocateListingIndex()
        listings.insert(newListing, at: 0)
        save()
    }

    func importPhotoFiles(from urls: [URL]) throws -> [URL] {
        let fileManager = FileManager.default
        let photosDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("EasySeloger/Photos", isDirectory: true)
        try fileManager.createDirectory(
            at: photosDirectory,
            withIntermediateDirectories: true
        )

        return try urls.map { sourceURL in
            let hasSecurityAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let fileExtension = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
            let destinationURL = photosDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            try Data(contentsOf: sourceURL).write(to: destinationURL, options: .atomic)
            return destinationURL
        }
    }

    func update(_ listing: PropertyListing) {
        guard let index = listings.firstIndex(where: { $0.id == listing.id }) else { return }
        listings[index] = listing
        save()
    }

    func delete(at offsets: IndexSet) {
        let deletedIDs = offsets.map { listings[$0].id }
        listings.remove(atOffsets: offsets)
        favoriteIDs.subtract(deletedIDs)
        save()
    }

    func delete(_ listing: PropertyListing) {
        listings.removeAll { $0.id == listing.id }
        favoriteIDs.remove(listing.id)
        save()
    }

    func toggleFavorite(_ listing: PropertyListing) {
        if favoriteIDs.contains(listing.id) {
            favoriteIDs.remove(listing.id)
        } else {
            favoriteIDs.insert(listing.id)
        }
        save()
    }

    func isFavorite(_ listing: PropertyListing) -> Bool {
        favoriteIDs.contains(listing.id)
    }

    func statusPriority(_ status: ListingStatus) -> Int {
        statuses.firstIndex(where: { $0.rawValue == status.rawValue }) ?? statuses.count
    }

    func addStatus(named name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !statuses.contains(where: {
                  $0.rawValue.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
              }) else {
            return false
        }

        statuses.append(ListingStatus(rawValue: trimmedName))
        saveStatuses()
        return true
    }

    func updateStatus(
        _ originalStatus: ListingStatus,
        name: String,
        colorChoice: ListingStatusColor
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !statuses.contains(where: {
                  $0.rawValue != originalStatus.rawValue
                      && $0.rawValue.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
              }),
              let statusIndex = statuses.firstIndex(where: {
                  $0.rawValue == originalStatus.rawValue
              }) else {
            return false
        }

        let updatedStatus = ListingStatus(
            rawValue: trimmedName,
            colorChoice: colorChoice
        )
        var updatedStatuses = statuses
        updatedStatuses[statusIndex] = updatedStatus
        statuses = updatedStatuses
        listings = listings.map { listing in
            guard listing.status.rawValue == originalStatus.rawValue else {
                return listing
            }
            var updatedListing = listing
            updatedListing.status = updatedStatus
            return updatedListing
        }
        saveStatuses()
        save()
        return true
    }

    func moveStatuses(from source: IndexSet, to destination: Int) {
        statuses.move(fromOffsets: source, toOffset: destination)
        saveStatuses()
    }

    func moveStatus(_ status: ListingStatus, by offset: Int) {
        guard let sourceIndex = statuses.firstIndex(of: status) else { return }
        let destinationIndex = sourceIndex + offset
        guard statuses.indices.contains(destinationIndex) else { return }

        statuses.swapAt(sourceIndex, destinationIndex)
        saveStatuses()
    }

    func moveStatus(withID sourceID: String, to target: ListingStatus) -> Bool {
        guard let sourceIndex = statuses.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = statuses.firstIndex(of: target),
              sourceIndex != targetIndex else {
            return false
        }

        let status = statuses.remove(at: sourceIndex)
        let destination = sourceIndex < targetIndex ? targetIndex : targetIndex
        statuses.insert(status, at: destination)
        saveStatuses()
        return true
    }

    func deleteStatuses(at offsets: IndexSet) -> Bool {
        let candidates = offsets.map { statuses[$0] }
        let candidateNames = Set(candidates.map(\.rawValue))
        guard statuses.count > candidates.count,
              !listings.contains(where: { candidateNames.contains($0.status.rawValue) }) else {
            return false
        }

        statuses.remove(atOffsets: offsets)
        saveStatuses()
        return true
    }

    fileprivate func makeBackupDocument() throws -> EasySelogerBackupDocument {
        let backup = EasySelogerBackup(
            formatVersion: EasySelogerBackup.currentFormatVersion,
            exportedAt: .now,
            listings: listings,
            favoriteIDs: favoriteIDs.sorted { $0.uuidString < $1.uuidString },
            statuses: statuses
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return EasySelogerBackupDocument(data: try encoder.encode(backup))
    }

    fileprivate func readBackup(from url: URL) throws -> EasySelogerBackup {
        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let backup = try JSONDecoder().decode(EasySelogerBackup.self, from: Data(contentsOf: url))
        guard backup.formatVersion == EasySelogerBackup.currentFormatVersion else {
            throw BackupError.unsupportedFormat
        }
        return backup
    }

    fileprivate func restore(_ backup: EasySelogerBackup) {
        apply(backup)
        markLocalChange()
        scheduleCloudUpload()
    }

    private func apply(_ backup: EasySelogerBackup) {
        isApplyingCloudBackup = true
        defer { isApplyingCloudBackup = false }

        listings = backup.listings
        migrateListingIndexesIfNeeded()
        let listingIDs = Set(listings.map(\.id))
        favoriteIDs = Set(backup.favoriteIDs).intersection(listingIDs)
        if let restoredStatuses = backup.statuses, !restoredStatuses.isEmpty {
            statuses = restoredStatuses
        }
        appendMissingStatusesUsedByListings()
        normalizeListingStatuses()
        persistLocally()
    }

    private func mergingLocalData(
        into cloudBackup: EasySelogerBackup,
        prefersLocalListings: Bool = false
    ) -> (backup: EasySelogerBackup, containsLocalOnlyData: Bool) {
        var mergedListings = cloudBackup.listings
        var containsLocalOnlyData = false

        for localListing in listings {
            let matchingIndex = mergedListings.firstIndex { cloudListing in
                cloudListing.id == localListing.id
                    || cloudListing.sourceURL.path == localListing.sourceURL.path
            }

            if let matchingIndex {
                if prefersLocalListings, mergedListings[matchingIndex] != localListing {
                    mergedListings[matchingIndex] = localListing
                    containsLocalOnlyData = true
                }
                continue
            }

            mergedListings.append(localListing)
            containsLocalOnlyData = true
        }

        let mergedListingIDs = Set(mergedListings.map(\.id))
        let mergedFavoriteIDs = Set(cloudBackup.favoriteIDs)
            .union(favoriteIDs)
            .intersection(mergedListingIDs)
        var mergedStatuses = cloudBackup.statuses ?? []
        for localStatus in statuses
        where !mergedStatuses.contains(where: { $0.rawValue == localStatus.rawValue }) {
            mergedStatuses.append(localStatus)
            containsLocalOnlyData = true
        }

        if mergedFavoriteIDs != Set(cloudBackup.favoriteIDs) {
            containsLocalOnlyData = true
        }

        return (
            EasySelogerBackup(
                formatVersion: cloudBackup.formatVersion,
                exportedAt: cloudBackup.exportedAt,
                listings: mergedListings,
                favoriteIDs: mergedFavoriteIDs.sorted { $0.uuidString < $1.uuidString },
                statuses: mergedStatuses
            ),
            containsLocalOnlyData
        )
    }

    private func load() {
        let savedListingsData = UserDefaults.standard.data(forKey: listingsKey)
        if let data = savedListingsData,
           let decoded = try? JSONDecoder().decode([PropertyListing].self, from: data) {
            listings = decoded.enumerated().map { index, listing in
                var cleanedListing = listing
                cleanedListing.title = SeLogerImporter.cleanedTitle(listing.title)
                cleanedListing.agencyName = SeLogerImporter.cleanedAgencyName(listing.agencyName)
                if cleanedListing.addedAt == nil {
                    cleanedListing.addedAt = Date(
                        timeIntervalSince1970: Double(decoded.count - index)
                    )
                }
                return cleanedListing
            }
        } else {
            listings = [.sample]
        }

        if let savedModificationDate = UserDefaults.standard.object(forKey: localModificationDateKey) as? Date {
            localModificationDate = savedModificationDate
        } else if savedListingsData != nil {
            localModificationDate = .now
            UserDefaults.standard.set(localModificationDate, forKey: localModificationDateKey)
        }

        let savedStatuses: [ListingStatus]
        if let data = UserDefaults.standard.data(forKey: statusesKey),
           let decodedStatuses = try? JSONDecoder().decode([ListingStatus].self, from: data) {
            savedStatuses = decodedStatuses
        } else {
            savedStatuses = UserDefaults.standard.stringArray(forKey: statusesKey)?
                .map { name in
                    ListingStatus.defaultOrder.first(where: { $0.rawValue == name })
                        ?? ListingStatus(rawValue: name)
                } ?? []
        }
        statuses = savedStatuses.isEmpty ? ListingStatus.defaultOrder : savedStatuses
        appendMissingStatusesUsedByListings()
        normalizeListingStatuses()
        saveStatuses()

        let savedFavoriteIDs = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        favoriteIDs = Set(savedFavoriteIDs.compactMap(UUID.init(uuidString:)))
        if migrateListingIndexesIfNeeded() {
            save()
        }
    }

    @discardableResult
    private func migrateListingIndexesIfNeeded() -> Bool {
        let missingIndices = listings.indices
            .filter { listings[$0].additionIndex == nil }
            .sorted { first, second in
                let firstDate = listings[first].addedAt ?? .distantPast
                let secondDate = listings[second].addedAt ?? .distantPast
                if firstDate != secondDate {
                    return firstDate < secondDate
                }
                return listings[first].id.uuidString < listings[second].id.uuidString
            }

        var nextIndex = (listings.compactMap(\.additionIndex).max() ?? 0) + 1
        for index in missingIndices {
            listings[index].additionIndex = nextIndex
            nextIndex += 1
        }

        let storedNextIndex = UserDefaults.standard.integer(forKey: nextListingIndexKey)
        UserDefaults.standard.set(max(storedNextIndex, nextIndex), forKey: nextListingIndexKey)
        return !missingIndices.isEmpty
    }

    private func allocateListingIndex() -> Int {
        let highestExistingIndex = listings.compactMap(\.additionIndex).max() ?? 0
        let storedNextIndex = UserDefaults.standard.integer(forKey: nextListingIndexKey)
        let nextIndex = max(storedNextIndex, highestExistingIndex + 1)
        UserDefaults.standard.set(nextIndex + 1, forKey: nextListingIndexKey)
        return nextIndex
    }

    private func appendMissingStatusesUsedByListings() {
        for status in listings.map(\.status)
        where !statuses.contains(where: { $0.rawValue == status.rawValue }) {
            statuses.append(status)
        }
    }

    private func normalizeListingStatuses() {
        for index in listings.indices {
            guard let configuredStatus = statuses.first(where: {
                $0.rawValue == listings[index].status.rawValue
            }) else {
                continue
            }
            listings[index].status = configuredStatus
        }
    }

    private func saveStatuses() {
        guard let data = try? JSONEncoder().encode(statuses) else { return }
        UserDefaults.standard.set(data, forKey: statusesKey)
        markLocalChange()
        scheduleCloudUpload()
    }

    private func save() {
        markLocalChange()
        persistLocally()
        scheduleCloudUpload()
    }

    private func markLocalChange() {
        guard !isApplyingCloudBackup else { return }
        localMutationGeneration += 1
        localModificationDate = .now
        UserDefaults.standard.set(localModificationDate, forKey: localModificationDateKey)
    }

    private func persistLocally() {
        guard let listingsData = try? JSONEncoder().encode(listings),
              let statusesData = try? JSONEncoder().encode(statuses) else {
            return
        }
        UserDefaults.standard.set(listingsData, forKey: listingsKey)
        UserDefaults.standard.set(statusesData, forKey: statusesKey)
        UserDefaults.standard.set(favoriteIDs.map(\.uuidString), forKey: favoritesKey)
    }

    private func scheduleCloudUpload() {
        guard !isApplyingCloudBackup else { return }
        cloudSyncStatus = .syncing
        cloudUploadTask?.cancel()
        cloudUploadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                try await self.uploadToCloud()
                self.cloudSyncStatus = .synced
                self.cloudSyncErrorMessage = nil
            } catch is CancellationError {
                return
            } catch let error as CKError where error.code == .operationCancelled {
                return
            } catch {
                self?.cloudSyncStatus = .failed
                self?.cloudSyncErrorMessage = "Sauvegarde iCloud impossible : \(error.localizedDescription)"
            }
        }
    }

    private func uploadToCloud() async throws {
        let mutationGenerationAtStart = localMutationGeneration
        let localBackup = EasySelogerBackup(
            formatVersion: EasySelogerBackup.currentFormatVersion,
            exportedAt: .now,
            listings: listings,
            favoriteIDs: favoriteIDs.sorted { $0.uuidString < $1.uuidString },
            statuses: statuses
        )
        let mergedBackup = try await CloudSyncService.saveMerging(localBackup)

        if mutationGenerationAtStart == localMutationGeneration {
            apply(mergedBackup)
            localModificationDate = mergedBackup.exportedAt
            UserDefaults.standard.set(
                mergedBackup.exportedAt,
                forKey: localModificationDateKey
            )
        }
    }
}

private struct ImportRequest: Identifiable {
    let id = UUID()
    let url: URL?
    let automaticallyImports: Bool
}

private enum ListingSortOrder: String, CaseIterable, Identifiable {
    case chronological
    case status

    var id: Self { self }

    var title: String {
        switch self {
        case .chronological: "Chronologique"
        case .status: "Par statut"
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var store = PropertyStore()
    @State private var importRequest: ImportRequest?
    @State private var isPresentingManualEntry = false
    @State private var editingListing: PropertyListing?
    @State private var isPresentingSettings = false
    @State private var searchText = ""
    @AppStorage("showsFavoritesOnly") private var showsFavoritesOnly = false
    @AppStorage("listingSortOrder") private var sortOrder = ListingSortOrder.chronological

    private var usesPortraitPhoneLayout: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    private var cloudSyncToolbarPlacement: ToolbarItemPlacement {
#if os(iOS)
        usesPortraitPhoneLayout ? .topBarLeading : .automatic
#else
        .automatic
#endif
    }

    private var displayedListings: [PropertyListing] {
        let favoritesFilteredListings = showsFavoritesOnly
            ? store.listings.filter(store.isFavorite)
            : store.listings
        let filteredListings = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? favoritesFilteredListings
            : favoritesFilteredListings.filter(matchesSearch)

        return filteredListings.sorted { first, second in
            switch sortOrder {
            case .chronological:
                return (first.addedAt ?? .distantPast) > (second.addedAt ?? .distantPast)
            case .status:
                let firstPriority = store.statusPriority(first.status)
                let secondPriority = store.statusPriority(second.status)
                if firstPriority != secondPriority {
                    return firstPriority < secondPriority
                }
                return (first.addedAt ?? .distantPast) > (second.addedAt ?? .distantPast)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.listings.isEmpty {
                    ContentUnavailableView(
                        "Aucun bien enregistré",
                        systemImage: "building.2",
                        description: Text("Ajoutez une annonce SeLoger ou un bien manuellement.")
                    )
                } else if displayedListings.isEmpty {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView(
                            "Aucun favori",
                            systemImage: "star",
                            description: Text("Ajoutez un bien aux favoris ou désactivez le filtre.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                } else {
                    List {
                        ForEach(displayedListings) { listing in
                            NavigationLink(value: listing.id) {
                                ListingRow(
                                    listing: listing,
                                    isFavorite: store.isFavorite(listing)
                                )
                            }
                            .listRowSeparator(.visible, edges: .bottom)
                            .listRowSeparatorTint(Color.primary.opacity(0.4), edges: .bottom)
                            .contextMenu {
                                Button {
                                    editingListing = listing
                                } label: {
                                    Label("Éditer", systemImage: "pencil")
                                }

                                Button {
                                    importRequest = ImportRequest(
                                        url: listing.sourceURL,
                                        automaticallyImports: true
                                    )
                                } label: {
                                    Label("Actualiser depuis SeLoger", systemImage: "arrow.clockwise")
                                }

                                Button {
                                    store.toggleFavorite(listing)
                                } label: {
                                    Label(
                                        store.isFavorite(listing) ? "Retirer des favoris" : "Ajouter aux favoris",
                                        systemImage: store.isFavorite(listing) ? "star.slash" : "star"
                                    )
                                }

                                Divider()

                                Button("Supprimer", systemImage: "trash", role: .destructive) {
                                    store.delete(listing)
                                }
                            }
                        }
                        .onDelete(perform: deleteDisplayedListings)
                    }
                    .listStyle(.plain)
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }

                while !Task.isCancelled {
                    await store.refreshFromCloud()

                    do {
                        try await Task.sleep(for: .seconds(10))
                    } catch {
                        return
                    }
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .cloudKitDataDidChange) {
                    await store.refreshFromCloud()
                }
            }
            .searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: "Rechercher un bien"
            )
            .navigationDestination(for: UUID.self) { id in
                if let listing = store.listings.first(where: { $0.id == id }) {
                    ListingDetailView(
                        listing: listing,
                        statuses: store.statuses,
                        onSave: store.update
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: cloudSyncToolbarPlacement) {
                    CloudSyncIndicator(status: store.cloudSyncStatus)
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItemGroup(placement: .automatic) {
                    if usesPortraitPhoneLayout {
                        Menu {
                            Picker("Classement", selection: $sortOrder) {
                                ForEach(ListingSortOrder.allCases) { order in
                                    Text(order.title).tag(order)
                                }
                            }
                        } label: {
                            Label {
                                Text("Classement : \(sortOrder.title)")
                            } icon: {
                                Image(systemName: "arrow.up.arrow.down")
                            }
                        }
                        .help("Choisir l’ordre d’affichage des biens")
                        .accessibilityLabel("Classement des biens")
                        .accessibilityValue(sortOrder.title)
                    } else {
                        Picker("Classement", selection: $sortOrder) {
                            ForEach(ListingSortOrder.allCases) { order in
                                Text(order.title).tag(order)
                            }
                        }
                        .pickerStyle(.segmented)
                        .help("Choisir l’ordre d’affichage des biens")
                    }

                    NavigationLink {
                        VisitTimelineView(store: store)
                    } label: {
                        Label("Calendrier des visites", systemImage: "calendar")
                    }
                    .help("Afficher toutes les visites par ordre chronologique")

                    Button {
                        showsFavoritesOnly.toggle()
                    } label: {
                        Label(
                            "Favoris",
                            systemImage: showsFavoritesOnly ? "star.fill" : "star"
                        )
                    }
                    .foregroundStyle(showsFavoritesOnly ? Color.yellow : Color.primary)
                    .help(showsFavoritesOnly ? "Afficher tous les biens" : "Afficher uniquement les favoris")
                    .accessibilityValue(showsFavoritesOnly ? "Filtre activé" : "Filtre désactivé")

                    Button("Réglages", systemImage: "slider.horizontal.3") {
                        isPresentingSettings = true
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Ajout manuel", systemImage: "square.and.pencil") {
                        isPresentingManualEntry = true
                    }

                    Button("Importer SeLoger", systemImage: "plus") {
                        showsFavoritesOnly = false
                        searchText = ""
                        importRequest = ImportRequest(
                            url: nil,
                            automaticallyImports: false
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(item: $importRequest) { request in
                AddListingView(
                    store: store,
                    initialURL: request.url,
                    automaticallyImports: request.automaticallyImports
                )
            }
            .sheet(isPresented: $isPresentingManualEntry) {
                ManualListingView(store: store)
            }
            .sheet(item: $editingListing) { listing in
                ManualListingView(store: store, listing: listing)
            }
            .sheet(isPresented: $isPresentingSettings) {
                SettingsView(store: store)
            }
            .alert("Impossible d’ajouter le bien", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private func matchesSearch(_ listing: PropertyListing) -> Bool {
        let searchableValues: [String] = ([
            listing.additionIndex.map(String.init),
            listing.title,
            listing.agencyName,
            listing.contactPhone,
            listing.neighborhood,
            listing.city,
            listing.preciseLocation,
            String(listing.price),
            listing.price.formatted(),
            String(listing.surface),
            listing.surface.formatted(),
            String(listing.rooms),
            String(listing.bedrooms),
            listing.summary,
            listing.analysis,
            listing.notes,
            listing.status.rawValue,
            listing.sourceURL.absoluteString,
            listing.imageURLs.map(\.absoluteString).joined(separator: " "),
            String(listing.latitude),
            String(listing.longitude),
            listing.addedAt?.formatted(date: .long, time: .shortened),
            listing.visitDate?.formatted(date: .long, time: .shortened),
            listing.publishedAt.formatted(date: .long, time: .omitted)
        ] as [String?]).compactMap { $0 }

        let searchableText = searchableValues
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let keywords = searchText
            .split(whereSeparator: \.isWhitespace)
            .map {
                String($0).folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
            }

        return keywords.allSatisfy(searchableText.contains)
    }

    private func deleteDisplayedListings(at offsets: IndexSet) {
        let listingsToDelete = offsets.map { displayedListings[$0] }
        for listing in listingsToDelete {
            store.delete(listing)
        }
    }
}

private struct VisitTimelineView: View {
    let store: PropertyStore

    private var scheduledVisits: [PropertyListing] {
        store.listings
            .filter { $0.visitDate != nil }
            .sorted {
                ($0.visitDate ?? .distantFuture) < ($1.visitDate ?? .distantFuture)
            }
    }

    var body: some View {
        Group {
            if scheduledVisits.isEmpty {
                ContentUnavailableView(
                    "Aucune visite programmée",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Les biens auxquels vous attribuez une date de visite apparaîtront ici.")
                )
            } else {
                List(scheduledVisits) { listing in
                    NavigationLink {
                        ListingDetailView(
                            listing: listing,
                            statuses: store.statuses,
                            onSave: store.update
                        )
                    } label: {
                        VisitTimelineRow(listing: listing)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Calendrier des visites")
    }
}

private struct VisitTimelineRow: View {
    let listing: PropertyListing

    private var address: String {
        if let preciseLocation = listing.preciseLocation,
           !preciseLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preciseLocation
        }

        return [listing.neighborhood, listing.city]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ListingPhotoStrip(
                urls: Array(listing.imageURLs.prefix(1)),
                listingIndex: listing.additionIndex,
                columnCount: 1,
                height: 92,
                usesCompactStyle: true
            )
            .frame(width: 120)

            VStack(alignment: .leading, spacing: 7) {
                if let visitDate = listing.visitDate {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(visitDate, format: .dateTime.weekday(.wide).day().month(.wide).year())
                            .font(.headline)

                        Spacer(minLength: 8)

                        Text(visitDate, format: .dateTime.hour().minute())
                            .font(.title2.bold())
                            .foregroundStyle(.tint)
                    }
                }

                Text("\(listing.price.formatted()) € · \(listing.surface.formatted(.number.precision(.fractionLength(0...2)))) m² · \(listing.pricePerSquareMeter.formatted()) €/m²")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Label(address.isEmpty ? "Adresse non renseignée" : address, systemImage: "mappin.and.ellipse")
                    .lineLimit(2)

                Label(listing.agencyName ?? "Contact non identifié", systemImage: "person.crop.circle")
                    .lineLimit(1)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct CloudSyncIndicator: View {
    let status: CloudSyncStatus

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 10, height: 10)
            .help(status.title)
            .accessibilityElement()
            .accessibilityLabel("État de la synchronisation iCloud")
            .accessibilityValue(status.title)
    }
}

private struct ListingRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let listing: PropertyListing
    let isFavorite: Bool

    private var usesPortraitPhoneLayout: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    var body: some View {
        let rowLayout = usesPortraitPhoneLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 18))

        rowLayout {
            VStack(alignment: .leading, spacing: usesPortraitPhoneLayout ? 5 : 8) {
                ListingPhotoStrip(
                    urls: Array(listing.imageURLs.prefix(usesPortraitPhoneLayout ? 2 : 3)),
                    listingIndex: listing.additionIndex,
                    columnCount: usesPortraitPhoneLayout ? 2 : 3,
                    height: usesPortraitPhoneLayout ? 118 : 210,
                    usesCompactStyle: usesPortraitPhoneLayout
                )

                ListingPhotoMetadata(
                    neighborhood: listing.neighborhood,
                    city: listing.city,
                    preciseLocation: listing.preciseLocation,
                    agencyName: listing.agencyName,
                    visitDate: listing.visitDate
                )
            }
            .frame(maxWidth: usesPortraitPhoneLayout ? .infinity : 720)
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    StatusBadge(status: listing.status)

                    Spacer()

                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(usesPortraitPhoneLayout ? .body : .title2)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favori")
                    }

                    if listing.hasExternalSource {
                        Link(destination: listing.sourceURL) {
                            Label("Voir l’annonce originale", systemImage: "arrow.up.right.square")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Voir l’annonce originale")
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\((Double(listing.price) / 1_000).formatted(.number.precision(.fractionLength(0...1)))) k€")
                            .font(usesPortraitPhoneLayout ? .headline.bold() : .title2.bold())

                        Text("\(listing.surface.formatted(.number.precision(.fractionLength(0...2)))) m²")
                            .font(usesPortraitPhoneLayout ? .headline.bold() : .title2.bold())

                        Text("· \(listing.pricePerSquareMeter.formatted()) €/m²")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Group {
                    if listing.notes.isEmpty {
                        Text("Notes : \(Text("Aucun commentaire").foregroundStyle(.secondary))")
                    } else {
                        Text("Notes : \(listing.notes)")
                    }
                }
                .font(usesPortraitPhoneLayout ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(usesPortraitPhoneLayout ? 3 : 6)

            }
            .frame(
                minWidth: usesPortraitPhoneLayout ? nil : 300,
                maxWidth: .infinity,
                minHeight: usesPortraitPhoneLayout ? nil : 234,
                alignment: .topLeading
            )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: usesPortraitPhoneLayout ? nil : 234,
            alignment: .leading
        )
        .foregroundStyle(.primary)
        .padding(.vertical, usesPortraitPhoneLayout ? 6 : 12)
        .clipped()
    }
}

private struct ListingPhotoMetadata: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let neighborhood: String
    let city: String
    let preciseLocation: String?
    let agencyName: String?
    let visitDate: Date?

    private var usesPortraitPhoneLayout: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    var body: some View {
        let metadataLayout = usesPortraitPhoneLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 16))

        metadataLayout {
            HStack(spacing: 4) {
                if let preciseLocation, !preciseLocation.isEmpty {
                    Label(preciseLocation, systemImage: "mappin.and.ellipse")
                } else {
                    Label("\(neighborhood), \(city)", systemImage: "mappin.and.ellipse")
                }
            }

            Label(agencyName ?? "Non identifié", systemImage: "building.2")

            if let visitDate {
                Label {
                    Text("Visite \(visitDate, format: .dateTime.day().month(.abbreviated).hour().minute())")
                } icon: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel(
                    Text("Visite prévue le \(visitDate, format: .dateTime.day().month(.wide).hour().minute())")
                )
            }
        }
        .font(usesPortraitPhoneLayout ? .caption2 : .caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct ListingPhotoStrip: View {
    let urls: [URL]
    let listingIndex: Int?
    let columnCount: Int
    let height: CGFloat
    let usesCompactStyle: Bool

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(max(0, columnCount - 1)) * 6
            let photoWidth = max(1, (geometry.size.width - totalSpacing) / CGFloat(columnCount))

            HStack(spacing: 6) {
                if urls.isEmpty {
                    indexedPhoto(
                        url: nil,
                        width: geometry.size.width,
                        cornerRadius: usesCompactStyle ? 10 : 16
                    )
                } else {
                    indexedPhoto(
                        url: urls[0],
                        width: photoWidth,
                        cornerRadius: usesCompactStyle ? 10 : 14
                    )

                    ForEach(urls.dropFirst(), id: \.absoluteString) { url in
                        PropertyImage(url: url)
                            .frame(width: photoWidth, height: height)
                            .clipShape(.rect(cornerRadius: usesCompactStyle ? 10 : 14))
                            .clipped()
                    }

                    ForEach(urls.count..<columnCount, id: \.self) { _ in
                        Rectangle()
                            .fill(.quaternary)
                            .frame(width: photoWidth, height: height)
                            .clipShape(.rect(cornerRadius: usesCompactStyle ? 10 : 14))
                    }
                }
            }
            .frame(width: geometry.size.width, height: height, alignment: .leading)
            .clipped()
        }
        .frame(height: height)
    }

    private func indexedPhoto(
        url: URL?,
        width: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            PropertyImage(url: url)
                .frame(width: width, height: height)
                .clipShape(.rect(cornerRadius: cornerRadius))
                .clipped()

            if let listingIndex {
                Text(listingIndex.formatted())
                    .font(.system(size: usesCompactStyle ? 30 : 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, usesCompactStyle ? 9 : 14)
                    .padding(.vertical, usesCompactStyle ? 3 : 6)
                    .background(.black.opacity(0.62), in: .rect(cornerRadius: usesCompactStyle ? 8 : 12))
                    .padding(usesCompactStyle ? 7 : 12)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
                    .accessibilityLabel("Appartement numéro \(listingIndex)")
            }
        }
        .frame(width: width, height: height)
    }
}

private struct PropertyImage: View {
    let url: URL?

    @ViewBuilder
    var body: some View {
        if let url, url.isFileURL {
            localImage(at: url)
        } else {
            AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                placeholder
            case .empty:
                placeholder
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                @unknown default:
                    placeholder
                }
            }
        }
    }

    @ViewBuilder
    private func localImage(at url: URL) -> some View {
#if os(macOS)
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            placeholder
        }
#elseif os(iOS)
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            placeholder
        }
#else
        placeholder
#endif
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "building.2.crop.circle")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
    }
}

private struct StatusBadge: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let status: ListingStatus

    private var usesPortraitPhoneLayout: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    var body: some View {
        Text(status.rawValue)
            .font(usesPortraitPhoneLayout ? .caption.bold() : .title2.bold())
            .foregroundStyle(status.color)
            .padding(.horizontal, usesPortraitPhoneLayout ? 10 : 16)
            .padding(.vertical, usesPortraitPhoneLayout ? 6 : 10)
            .background(status.color.opacity(0.14), in: .capsule)
    }
}

private enum ListingLocationResolver {
    static func coordinate(for preciseLocation: String?, city: String) async -> CLLocationCoordinate2D? {
        guard let preciseLocation = preciseLocation?.nilIfBlank else { return nil }

        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = trimmedCity.isEmpty || preciseLocation.localizedCaseInsensitiveContains(trimmedCity)
            ? preciseLocation
            : "\(preciseLocation), \(trimmedCity)"
        guard let request = MKGeocodingRequest(addressString: address) else { return nil }

        return try? await request.mapItems.first?.location.coordinate
    }
}

private struct ListingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var draft: PropertyListing
    @State private var selectedPhotoURL: URL?
    @State private var isMapFullScreenPresented = false
    let statuses: [ListingStatus]
    let onSave: (PropertyListing) -> Void

    init(
        listing: PropertyListing,
        statuses: [ListingStatus],
        onSave: @escaping (PropertyListing) -> Void
    ) {
        _draft = State(initialValue: listing)
        _selectedPhotoURL = State(initialValue: nil)
        self.statuses = statuses
        self.onSave = onSave
    }

    private var mapCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude)
    }

    private var geocodingQuery: String {
        "\(draft.preciseLocation ?? "")|\(draft.city)"
    }

    private var usesPortraitPhoneLayout: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    var body: some View {
        let headerLayout = usesPortraitPhoneLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))
        let notesMapLayout = usesPortraitPhoneLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))

        ScrollView {
            LazyVStack(alignment: .leading, spacing: usesPortraitPhoneLayout ? 14 : 22) {
                if draft.hasExternalSource {
                    Link(destination: draft.sourceURL) {
                        Label("Voir l’annonce originale", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                PhotoGallery(
                    urls: draft.imageURLs,
                    onSelect: { url in
                        selectedPhotoURL = url
                    },
                    onDelete: { url in
                        draft.imageURLs.removeAll { $0 == url }
                        if selectedPhotoURL == url {
                            selectedPhotoURL = nil
                        }
                        onSave(draft)
                    }
                )

                VStack(alignment: .leading, spacing: 8) {
                    headerLayout {
                        if let additionIndex = draft.additionIndex {
                            Text(additionIndex.formatted())
                                .font(.system(size: usesPortraitPhoneLayout ? 28 : 42, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.72), in: .rect(cornerRadius: 10))
                                .accessibilityLabel("Appartement numéro \(additionIndex)")
                        }

                        Text(draft.price, format: .currency(code: "EUR").precision(.fractionLength(0)))
                            .font(usesPortraitPhoneLayout ? .title.bold() : .largeTitle.bold())

                        Text("\(draft.surface.formatted(.number.precision(.fractionLength(0...2)))) m² · \(draft.pricePerSquareMeter.formatted()) €/m²")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Label("\(draft.neighborhood), \(draft.city)", systemImage: "mappin.and.ellipse")
                            if let preciseLocation = draft.preciseLocation?.nilIfBlank {
                                Text("· \(preciseLocation)")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                        Spacer()

                        Picker("Statut", selection: $draft.status) {
                            ForEach(statuses) { status in
                                Text(status.rawValue).tag(status)
                            }
                        }
                    }

                    if let agencyName = draft.agencyName {
                        Label("Contact : \(agencyName)", systemImage: "building.2")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                }

                FactsGrid(listing: draft)

                GeometryReader { geometry in
                    notesMapLayout {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes :")
                                .font(.headline)
                            TextEditor(text: $draft.notes)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(8)
                                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                        }

                        Map(position: .constant(.region(MKCoordinateRegion(
                            center: mapCoordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                        )))) {
                            Marker(draft.preciseLocation ?? draft.neighborhood, coordinate: mapCoordinate)
                        }
                        .frame(
                            width: usesPortraitPhoneLayout ? geometry.size.width : geometry.size.width * 0.25,
                            height: usesPortraitPhoneLayout ? 135 : nil
                        )
                        .clipShape(.rect(cornerRadius: 18))
#if os(iOS)
                        .highPriorityGesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    if UIDevice.current.userInterfaceIdiom == .pad {
                                        isMapFullScreenPresented = true
                                    }
                                }
                        )
#elseif os(macOS)
                        .highPriorityGesture(
                            TapGesture(count: 2)
                                .onEnded { openLocationInMaps() }
                        )
#endif
                        .accessibilityLabel("Carte du quartier \(draft.neighborhood)")
                    }
                }
                .frame(height: usesPortraitPhoneLayout ? 300 : 230)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Contact et localisation", systemImage: "person.crop.circle")
                        .font(.headline)

                    VisitDateEditor(date: $draft.visitDate)

                    LabeledContent("Nom du contact") {
                        TextField(
                            "Nom du contact",
                            text: Binding(
                                get: { draft.agencyName ?? "" },
                                set: {
                                    draft.agencyName = $0.isEmpty ? nil : $0
                                    draft.isContactNameManuallyEdited = true
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Téléphone du contact") {
                        TextField(
                            "Téléphone du contact",
                            text: Binding(
                                get: { draft.contactPhone ?? "" },
                                set: {
                                    draft.contactPhone = $0.isEmpty ? nil : $0
                                    draft.isContactPhoneManuallyEdited = true
                                }
                            )
                        )
                        .textContentType(.telephoneNumber)
                        .textFieldStyle(.roundedBorder)
                    }

                    LabeledContent("Localisation précise") {
                        TextField(
                            "Localisation précise",
                            text: Binding(
                                get: { draft.preciseLocation ?? "" },
                                set: { draft.preciseLocation = $0.isEmpty ? nil : $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))

            }
            .padding(usesPortraitPhoneLayout ? 10 : 16)
        }
        .navigationTitle("Retour")
        .task(id: geocodingQuery) {
            await resolvePreciseLocation()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Retour") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
#if os(macOS)
        .sheet(isPresented: Binding(
            get: { selectedPhotoURL != nil },
            set: { if !$0 { selectedPhotoURL = nil } }
        )) {
            if selectedPhotoURL != nil {
                EnlargedPhotoView(
                    urls: draft.imageURLs,
                    selectedURL: $selectedPhotoURL
                )
                    .frame(
                        minWidth: 1_200,
                        idealWidth: 1_400,
                        minHeight: 800,
                        idealHeight: 900
                    )
            }
        }
#else
        .fullScreenCover(isPresented: Binding(
            get: { selectedPhotoURL != nil },
            set: { if !$0 { selectedPhotoURL = nil } }
        )) {
            if selectedPhotoURL != nil {
                EnlargedPhotoView(
                    urls: draft.imageURLs,
                    selectedURL: $selectedPhotoURL
                )
            }
        }
        .fullScreenCover(isPresented: $isMapFullScreenPresented) {
            FullScreenListingMap(
                coordinate: mapCoordinate,
                title: draft.preciseLocation ?? draft.neighborhood
            )
        }
#endif
        .onDisappear { onSave(draft) }
    }

#if os(macOS)
    private func openLocationInMaps() {
        let location = CLLocation(
            latitude: mapCoordinate.latitude,
            longitude: mapCoordinate.longitude
        )
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = draft.preciseLocation?.nilIfBlank
            ?? "\(draft.neighborhood), \(draft.city)"
        mapItem.openInMaps()
    }
#endif

    private func resolvePreciseLocation() async {
        guard draft.preciseLocation?.nilIfBlank != nil else { return }

        do {
            try await Task.sleep(for: .milliseconds(600))
        } catch {
            return
        }

        guard let coordinate = await ListingLocationResolver.coordinate(
            for: draft.preciseLocation,
            city: draft.city
        ), !Task.isCancelled else {
            return
        }

        draft.latitude = coordinate.latitude
        draft.longitude = coordinate.longitude
    }
}

#if os(iOS)
private struct FullScreenListingMap: View {
    @Environment(\.dismiss) private var dismiss

    let coordinate: CLLocationCoordinate2D
    let title: String
    @State private var position: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D, title: String) {
        self.coordinate = coordinate
        self.title = title
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        )))
    }

    var body: some View {
        Map(position: $position) {
            Marker(title, coordinate: coordinate)
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button("Fermer", systemImage: "xmark.circle.fill") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .font(.largeTitle)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.65))
            .padding()
            .accessibilityLabel("Fermer la carte")
        }
    }
}
#endif

private struct PhotoGallery: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let urls: [URL]

    private var usesPortraitPhoneLayout: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    let onSelect: (URL) -> Void
    let onDelete: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(urls, id: \.absoluteString) { url in
                    Button {
                        onSelect(url)
                    } label: {
                        PropertyImage(url: url)
                            .frame(
                                width: usesPortraitPhoneLayout ? 260 : 420,
                                height: usesPortraitPhoneLayout ? 170 : 280
                            )
                            .clipShape(.rect(cornerRadius: usesPortraitPhoneLayout ? 12 : 20))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Afficher la photo en grand")
                    .contextMenu {
                        Button("Supprimer photo", systemImage: "trash", role: .destructive) {
                            onDelete(url)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: usesPortraitPhoneLayout ? 170 : 280)
    }
}

private struct EnlargedPhotoView: View {
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    @Binding var selectedURL: URL?

    private var selectedIndex: Int? {
        guard let selectedURL else { return nil }
        return urls.firstIndex(of: selectedURL)
    }

    private var canShowPrevious: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex > urls.startIndex
    }

    private var canShowNext: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex < urls.index(before: urls.endIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: selectedURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    ContentUnavailableView("Photo indisponible", systemImage: "photo")
                        .foregroundStyle(.white)
                case .empty:
                    ProgressView()
                        .tint(.white)
                @unknown default:
                    EmptyView()
                }
            }
            .padding(24)
        }
#if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
#endif
        .overlay(alignment: .topTrailing) {
            Button("Fermer", systemImage: "xmark.circle.fill") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .font(.title)
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .padding()
        }
#if os(macOS)
        .overlay {
            HStack {
                navigationButton(
                    title: "Photo précédente",
                    systemImage: "chevron.left",
                    key: .leftArrow,
                    isEnabled: canShowPrevious,
                    action: showPrevious
                )

                Spacer()

                navigationButton(
                    title: "Photo suivante",
                    systemImage: "chevron.right",
                    key: .rightArrow,
                    isEnabled: canShowNext,
                    action: showNext
                )
            }
            .padding()
        }
#endif
    }

#if os(macOS)
    private func navigationButton(
        title: String,
        systemImage: String,
        key: KeyEquivalent,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.largeTitle)
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .keyboardShortcut(key, modifiers: [])
            .disabled(!isEnabled)
            .accessibilityLabel(title)
    }

    private func showPrevious() {
        guard let selectedIndex, canShowPrevious else { return }
        selectedURL = urls[urls.index(before: selectedIndex)]
    }

    private func showNext() {
        guard let selectedIndex, canShowNext else { return }
        selectedURL = urls[urls.index(after: selectedIndex)]
    }
#endif
}

private struct FactsGrid: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let listing: PropertyListing

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact && verticalSizeClass == .regular ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            FactCard(value: "\(listing.surface.formatted(.number.precision(.fractionLength(0)))) m²", label: "Surface")
            FactCard(value: "\(listing.rooms)", label: "Pièces")
            FactCard(value: "\(listing.bedrooms)", label: "Chambres")
            FactCard(value: "\(listing.pricePerSquareMeter.formatted()) €", label: "Prix / m²")
        }
    }
}

private struct VisitDateEditor: View {
    @Binding var date: Date?

    var body: some View {
        Toggle("Date de visite", isOn: Binding(
            get: { date != nil },
            set: { isEnabled in
                date = isEnabled ? (date ?? .now) : nil
            }
        ))

        if date != nil {
            DatePicker(
                "Date et heure",
                selection: Binding(
                    get: { date ?? .now },
                    set: { date = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }
}

private struct FactCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(horizontalSizeClass == .compact && verticalSizeClass == .regular ? 8 : 16)
        .background(.quaternary.opacity(0.55), in: .rect(cornerRadius: 14))
    }
}

private struct ManualListingView: View {
    @Environment(\.dismiss) private var dismiss

    let store: PropertyStore
    let listing: PropertyListing?

    @State private var title = ""
    @State private var price = ""
    @State private var surface = ""
    @State private var rooms = ""
    @State private var bedrooms = ""
    @State private var neighborhood = ""
    @State private var city = "Montpellier"
    @State private var preciseLocation = ""
    @State private var agencyName = ""
    @State private var contactPhone = ""
    @State private var sourceURLText = ""
    @State private var summary = ""
    @State private var notes = ""
    @State private var status = ListingStatus.new
    @State private var visitDate: Date?
    @State private var imageURLs: [URL] = []
    @State private var imageURLText = ""
    @State private var isImportingPhotos = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(store: PropertyStore, listing: PropertyListing? = nil) {
        self.store = store
        self.listing = listing
        _title = State(initialValue: listing?.title ?? "")
        _price = State(initialValue: listing.map { String($0.price) } ?? "")
        _surface = State(initialValue: listing.map { $0.surface.formatted(.number.precision(.fractionLength(0...2))) } ?? "")
        _rooms = State(initialValue: listing.map { String($0.rooms) } ?? "")
        _bedrooms = State(initialValue: listing.map { String($0.bedrooms) } ?? "")
        _neighborhood = State(initialValue: listing?.neighborhood ?? "")
        _city = State(initialValue: listing?.city ?? "Montpellier")
        _preciseLocation = State(initialValue: listing?.preciseLocation ?? "")
        _agencyName = State(initialValue: listing?.agencyName ?? "")
        _contactPhone = State(initialValue: listing?.contactPhone ?? "")
        _sourceURLText = State(initialValue: listing?.hasExternalSource == true ? listing?.sourceURL.absoluteString ?? "" : "")
        _summary = State(initialValue: listing?.summary ?? "")
        _notes = State(initialValue: listing?.notes ?? "")
        _status = State(initialValue: listing?.status ?? .new)
        _visitDate = State(initialValue: listing?.visitDate)
        _imageURLs = State(initialValue: listing?.imageURLs ?? [])
    }

    private var parsedPrice: Int? {
        Int(price.filter(\.isNumber))
    }

    private var parsedSurface: Double? {
        Double(surface.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedPrice.map { $0 > 0 } == true
            && parsedSurface.map { $0 > 0 } == true
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (sourceURLText.nilIfBlank == nil || validSourceURL != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Informations principales") {
                    TextField("Titre de l’annonce", text: $title)
                    TextField("Prix (€)", text: $price)
                    TextField("Surface (m²)", text: $surface)
                    TextField("Nombre de pièces", text: $rooms)
                    TextField("Nombre de chambres", text: $bedrooms)
                    Picker("Statut", selection: $status) {
                        ForEach(store.statuses) { listingStatus in
                            Text(listingStatus.rawValue).tag(listingStatus)
                        }
                    }
                    VisitDateEditor(date: $visitDate)
                }

                Section("Localisation") {
                    TextField("Quartier", text: $neighborhood)
                    TextField("Ville", text: $city)
                    TextField("Adresse ou localisation précise", text: $preciseLocation)
                }

                Section("Annonce et contact") {
                    TextField("URL de l’annonce (facultatif)", text: $sourceURLText)
                    TextField("Agence ou contact", text: $agencyName)
                    TextField("Téléphone", text: $contactPhone)
                }

                Section("Description et commentaires") {
                    TextField("Description du bien", text: $summary, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Mes commentaires", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    HStack {
                        TextField("https://exemple.com/photo.jpg", text: $imageURLText)
                            .onSubmit(addImageURL)

                        Button("Ajouter l’URL", systemImage: "link.badge.plus") {
                            addImageURL()
                        }
                        .disabled(validImageURL == nil)
                    }

                    Button("Importer des fichiers…", systemImage: "photo.on.rectangle.angled") {
                        isImportingPhotos = true
                    }

                    if imageURLs.isEmpty {
                        Text("Aucune photo ajoutée")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 12) {
                                ForEach(imageURLs, id: \.absoluteString) { url in
                                    PropertyImage(url: url)
                                        .frame(width: 160, height: 110)
                                        .clipShape(.rect(cornerRadius: 10))
                                        .overlay(alignment: .topTrailing) {
                                            Button("Retirer la photo", systemImage: "xmark.circle.fill") {
                                                imageURLs.removeAll { $0 == url }
                                            }
                                            .labelStyle(.iconOnly)
                                            .buttonStyle(.plain)
                                            .padding(6)
                                        }
                                }
                            }
                        }
                        .frame(height: 110)
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Ajoutez plusieurs fichiers image ou collez une URL directe vers une photo.")
                }
            }
            .formStyle(.grouped)
#if os(macOS)
            .frame(minWidth: 700, minHeight: 720)
#endif
            .navigationTitle(listing == nil ? "Nouveau bien" : "Éditer le bien")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .fileImporter(
                isPresented: $isImportingPhotos,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    do {
                        let importedURLs = try store.importPhotoFiles(from: urls)
                        appendUniqueImageURLs(importedURLs)
                    } catch {
                        errorMessage = "Import des photos impossible : \(error.localizedDescription)"
                    }
                case .failure(let error):
                    errorMessage = "Import des photos impossible : \(error.localizedDescription)"
                }
            }
            .alert(
                listing == nil ? "Ajout manuel" : "Modification du bien",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var validSourceURL: URL? {
        let candidate = sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: candidate),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return url
    }

    private var validImageURL: URL? {
        let candidate = imageURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: candidate),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return url
    }

    private func addImageURL() {
        guard let url = validImageURL else { return }
        appendUniqueImageURLs([url])
        imageURLText = ""
    }

    private func appendUniqueImageURLs(_ newURLs: [URL]) {
        let existingURLs = Set(imageURLs)
        imageURLs.append(contentsOf: newURLs.filter { !existingURLs.contains($0) })
    }

    private func save() async {
        guard let price = parsedPrice, let surface = parsedSurface else { return }

        isSaving = true
        defer { isSaving = false }

        let listingID = listing?.id ?? UUID()
        let sourceURL = validSourceURL
            ?? listing?.sourceURL
            ?? URL(string: "easyseloger://manual/\(listingID.uuidString)")
            ?? URL(fileURLWithPath: "/")
        let resolvedCoordinate = await ListingLocationResolver.coordinate(
            for: preciseLocation,
            city: city
        )

        let savedListing = PropertyListing(
            id: listingID,
            addedAt: listing?.addedAt,
            additionIndex: listing?.additionIndex,
            sourceURL: sourceURL,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            agencyName: agencyName.nilIfBlank,
            contactPhone: contactPhone.nilIfBlank,
            isContactNameManuallyEdited: true,
            isContactPhoneManuallyEdited: true,
            neighborhood: neighborhood.nilIfBlank ?? "Quartier non précisé",
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            preciseLocation: preciseLocation.nilIfBlank,
            price: price,
            surface: surface,
            rooms: Int(rooms.filter(\.isNumber)) ?? 0,
            bedrooms: Int(bedrooms.filter(\.isNumber)) ?? 0,
            publishedAt: listing?.publishedAt ?? .now,
            visitDate: visitDate,
            summary: summary.nilIfBlank ?? "Bien ajouté manuellement.",
            analysis: listing?.analysis ?? "Ce bien a été ajouté manuellement. Complétez les informations à vérifier dans vos commentaires.",
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURLs: imageURLs,
            latitude: resolvedCoordinate?.latitude ?? listing?.latitude ?? 43.6108,
            longitude: resolvedCoordinate?.longitude ?? listing?.longitude ?? 3.8767,
            status: status
        )

        if listing == nil {
            store.addManualListing(savedListing)
        } else {
            store.update(savedListing)
        }
        dismiss()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AddListingView: View {
    @Environment(\.dismiss) private var dismiss
    let store: PropertyStore
    let automaticallyImports: Bool
    @State private var urlText: String
    @State private var page: WebPage
    @State private var isLoadingPage = false
    @State private var didStartAutomaticFlow = false

    init(
        store: PropertyStore,
        initialURL: URL? = nil,
        automaticallyImports: Bool = false
    ) {
        self.store = store
        self.automaticallyImports = automaticallyImports
        _urlText = State(initialValue: initialURL?.absoluteString ?? "")
        _page = State(initialValue: SeLogerImporter.configuredPage())
    }

    private var url: URL? {
        URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isSeLogerURL: Bool {
        url?.host?.contains("seloger.com") == true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("https://www.seloger.com/annonce/…", text: $urlText)
                            .autocorrectionDisabled()
                            .onSubmit {
                                guard isSeLogerURL, !isLoadingPage else { return }
                                loadPage()
                            }

                        Button {
                            loadPage()
                        } label: {
                            if isLoadingPage {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Ouvrir", systemImage: "globe")
                            }
                        }
                        .disabled(!isSeLogerURL || isLoadingPage)
                    }

                    if page.url == nil {
                        ContentUnavailableView(
                            "Ouvrez d’abord l’annonce",
                            systemImage: "safari",
                            description: Text("La page apparaîtra ici. Acceptez les cookies ou terminez la vérification SeLoger avant de lancer l’import.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding()

                if page.url != nil {
                    Divider()
                    WebView(page)
                        .webViewBackForwardNavigationGestures(.enabled)
                        .overlay(alignment: .top) {
                            if isLoadingPage {
                                ProgressView()
                                    .padding(8)
                                    .background(.regularMaterial, in: .capsule)
                                    .padding()
                            }
                        }
                }
            }
#if os(macOS)
            .frame(minWidth: 1_200, minHeight: 680)
#endif
            .navigationTitle(automaticallyImports ? "Actualiser le bien" : "Importer une annonce")
            .task {
                guard automaticallyImports, !didStartAutomaticFlow else { return }
                didStartAutomaticFlow = true
                loadPage(shouldImportAfterLoad: true)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        importCurrentPage()
                    } label: {
                        if store.isImportingListing {
                            ProgressView()
                        } else {
                            Label("Importer la page", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(page.url == nil || store.isImportingListing || isLoadingPage)
                }
            }
            .alert("Import impossible", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private func loadPage(shouldImportAfterLoad: Bool = false) {
        guard let url, isSeLogerURL else { return }
        isLoadingPage = true
        store.errorMessage = nil

        Task {
            do {
                for try await _ in page.load(URLRequest(url: url)) {}
                isLoadingPage = false
                if shouldImportAfterLoad {
                    if await store.addListing(from: url, page: page) {
                        dismiss()
                    }
                }
            } catch {
                isLoadingPage = false
                store.errorMessage = "Chargement SeLoger impossible : \(error.localizedDescription)"
            }
        }
    }

    private func importCurrentPage() {
        guard let url else { return }
        store.errorMessage = nil
        Task {
            if await store.addListing(from: url, page: page) {
                dismiss()
            }
        }
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument: EasySelogerBackupDocument?
    @State private var pendingBackup: EasySelogerBackup?
    @State private var backupMessage: String?
    @State private var statusMessage: String?
    @State private var newStatusName = ""
    @State private var editingStatus: ListingStatus?
    let store: PropertyStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.statuses) { status in
                        HStack {
                            Circle()
                                .fill(status.color)
                                .frame(width: 10, height: 10)

                            Text(status.rawValue)

                            Spacer()

                            Button("Modifier", systemImage: "pencil") {
                                editingStatus = status
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Modifier « \(status.rawValue) »")

                            Button("Supprimer", systemImage: "minus.circle") {
                                deleteStatus(status)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Supprimer « \(status.rawValue) »")

                            #if os(macOS)
                            Button("Monter", systemImage: "chevron.up") {
                                withAnimation {
                                    store.moveStatus(status, by: -1)
                                }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .disabled(store.statuses.firstIndex(of: status) == 0)
                            .help("Monter « \(status.rawValue) »")

                            Button("Descendre", systemImage: "chevron.down") {
                                withAnimation {
                                    store.moveStatus(status, by: 1)
                                }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .disabled(store.statuses.firstIndex(of: status) == store.statuses.count - 1)
                            .help("Descendre « \(status.rawValue) »")
                            #else
                            Image(systemName: "line.3.horizontal")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .contentShape(.rect)
                                .draggable(status.id)
                                .accessibilityLabel("Déplacer le statut \(status.rawValue)")
                            #endif
                        }
                        #if os(iOS)
                        .dropDestination(for: String.self) { draggedStatusIDs, _ in
                            guard let draggedStatusID = draggedStatusIDs.first else {
                                return false
                            }
                            return store.moveStatus(withID: draggedStatusID, to: status)
                        }
                        #endif
                    }
                    .onMove(perform: store.moveStatuses)
                    .onDelete(perform: deleteStatuses)

                    HStack {
                        TextField("Nouveau statut", text: $newStatusName)
                            .onSubmit(addStatus)

                        Button("Ajouter", systemImage: "plus") {
                            addStatus()
                        }
                        .disabled(newStatusName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Statuts")
                } footer: {
                    #if os(macOS)
                    Text("Utilisez les flèches pour définir l’ordre dans les menus et dans l’affichage « Par statut ».")
                    #else
                    Text("Faites glisser les statuts pour définir leur ordre dans les menus et dans l’affichage « Par statut ».")
                    #endif
                }

                Section {
                    Button("Exporter les données", systemImage: "square.and.arrow.up") {
                        prepareExport()
                    }

                    Button("Importer une sauvegarde", systemImage: "square.and.arrow.down") {
                        isImporting = true
                    }
                } header: {
                    Text("Sauvegarde")
                } footer: {
                    Text("Le fichier JSON contient les biens, favoris, commentaires, statuts et champs modifiés. L’import remplace la base actuelle après confirmation.")
                }
            }
            .navigationTitle("Réglages")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .automatic) {
                    EditButton()
                }
                #endif

                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $editingStatus) { status in
                StatusEditorView(status: status) { name, colorChoice in
                    guard store.updateStatus(
                        status,
                        name: name,
                        colorChoice: colorChoice
                    ) else {
                        statusMessage = "Ce nom est vide ou déjà utilisé par un autre statut."
                        return false
                    }
                    return true
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: backupFilename
            ) { result in
                switch result {
                case .success:
                    backupMessage = "La sauvegarde a bien été exportée."
                case .failure(let error):
                    backupMessage = "Export impossible : \(error.localizedDescription)"
                }
                exportDocument = nil
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        pendingBackup = try store.readBackup(from: url)
                    } catch {
                        backupMessage = "Import impossible : \(error.localizedDescription)"
                    }
                case .failure(let error):
                    backupMessage = "Import impossible : \(error.localizedDescription)"
                }
            }
            .confirmationDialog(
                "Remplacer la base actuelle ?",
                isPresented: Binding(
                    get: { pendingBackup != nil },
                    set: { if !$0 { pendingBackup = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Importer et remplacer", role: .destructive) {
                    if let pendingBackup {
                        store.restore(pendingBackup)
                        backupMessage = "La sauvegarde a bien été importée."
                    }
                    self.pendingBackup = nil
                }
                Button("Annuler", role: .cancel) {
                    pendingBackup = nil
                }
            } message: {
                Text("Les données actuellement enregistrées dans l’application seront remplacées par celles du fichier.")
            }
            .alert(
                "Statuts",
                isPresented: Binding(
                    get: { statusMessage != nil },
                    set: { if !$0 { statusMessage = nil } }
                )
            ) {
                Button("OK") {
                    statusMessage = nil
                }
            } message: {
                Text(statusMessage ?? "")
            }
            .alert(
                "Sauvegarde",
                isPresented: Binding(
                    get: { backupMessage != nil },
                    set: { if !$0 { backupMessage = nil } }
                )
            ) {
                Button("OK") {
                    backupMessage = nil
                }
            } message: {
                Text(backupMessage ?? "")
            }
        }
    }

    private var backupFilename: String {
        let date = ISO8601DateFormatter().string(from: .now).prefix(10)
        return "EasySeloger-\(date)"
    }

    private func addStatus() {
        guard store.addStatus(named: newStatusName) else {
            statusMessage = "Ce statut existe déjà ou son nom est vide."
            return
        }
        newStatusName = ""
    }

    private func deleteStatuses(at offsets: IndexSet) {
        guard store.deleteStatuses(at: offsets) else {
            statusMessage = "Un statut utilisé par un bien ne peut pas être supprimé. Il faut également conserver au moins un statut."
            return
        }
    }

    private func deleteStatus(_ status: ListingStatus) {
        guard let index = store.statuses.firstIndex(where: {
            $0.rawValue == status.rawValue
        }) else {
            return
        }
        deleteStatuses(at: IndexSet(integer: index))
    }

    private func prepareExport() {
        do {
            exportDocument = try store.makeBackupDocument()
            isExporting = true
        } catch {
            backupMessage = "Export impossible : \(error.localizedDescription)"
        }
    }
}

private struct StatusEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorChoice: ListingStatusColor

    let onSave: (String, ListingStatusColor) -> Bool

    init(
        status: ListingStatus,
        onSave: @escaping (String, ListingStatusColor) -> Bool
    ) {
        _name = State(initialValue: status.rawValue)
        _colorChoice = State(initialValue: status.colorChoice)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $name)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Couleur")

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(34), spacing: 10),
                            count: 7
                        ),
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(ListingStatusColor.allCases) { choice in
                            Button {
                                colorChoice = choice
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(choice.color)
                                        .frame(width: 28, height: 28)

                                    if colorChoice == choice {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .shadow(color: .black.opacity(0.6), radius: 1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(choice.title)
                            .accessibilityLabel(choice.title)
                            .accessibilityValue(colorChoice == choice ? "Sélectionnée" : "")
                        }
                    }

                    Text(colorChoice.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Aperçu")
                    Spacer()
                    Text(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colorChoice.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(colorChoice.color.opacity(0.14), in: .capsule)
                }
            }
            .navigationTitle("Modifier le statut")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if onSave(name, colorChoice) {
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}

#Preview {
    ContentView()
}
