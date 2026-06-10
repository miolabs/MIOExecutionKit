//
//  Models.swift
//  POSKit
//

import Foundation

public struct DocumentNumber: Codable, Sendable, CustomStringConvertible {
    public let prefix: String
    public let series: String
    public let number: Int

    public init(prefix: String, series: String, number: Int) {
        self.prefix = prefix
        self.series = series
        self.number = number
    }

    public var description: String {
        String(format: "%@-%@-%04d", prefix, series, number)
    }
}

public struct AccountCharge: Codable, Sendable {
    public let accountID: String
    public let amount: Decimal
    public let series: String

    public init(accountID: String, amount: Decimal, series: String) {
        self.accountID = accountID
        self.amount = amount
        self.series = series
    }
}

public struct AccountBalance: Codable, Sendable, CustomStringConvertible {
    public let accountID: String
    public let balance: Decimal
    public let lastDocument: DocumentNumber

    public init(accountID: String, balance: Decimal, lastDocument: DocumentNumber) {
        self.accountID = accountID
        self.balance = balance
        self.lastDocument = lastDocument
    }

    public var description: String {
        "\(accountID): \(balance) (last doc \(lastDocument))"
    }
}
