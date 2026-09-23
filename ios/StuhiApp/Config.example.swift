import Foundation

// Copy this file to Config.swift and fill in the values from ~/.stuhi-app/env.
// Config.swift is gitignored. The app uses ONLY the publishable key — the
// secret key must never appear in a client binary.
//
//   cp Config.example.swift Config.swift
//
// or run: scripts/make-config.sh

enum Config {
    static let supabaseURL = "https://YOUR-PROJECT.supabase.co"
    static let supabasePublishableKey = "sb_publishable_..."
}
