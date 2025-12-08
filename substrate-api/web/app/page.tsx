"use client";

import Link from "next/link";

export default function LandingPage() {
  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="border-b border-neutral-200 bg-white">
        <div className="max-w-7xl mx-auto px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 bg-black rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-sm">CH</span>
            </div>
            <span className="font-semibold text-lg">Clearinghouse</span>
          </div>
          <nav className="flex items-center gap-6">
            <Link href="/docs" className="text-neutral-600 hover:text-black">
              Documentation
            </Link>
            <Link
              href="/auth/login"
              className="bg-black text-white px-4 py-2 rounded-lg hover:bg-neutral-800 transition"
            >
              Sign In
            </Link>
          </nav>
        </div>
      </header>

      {/* Hero */}
      <section className="max-w-7xl mx-auto px-6 py-24">
        <div className="max-w-3xl">
          <h1 className="text-5xl md:text-6xl font-bold tracking-tight mb-6">
            IP Licensing Infrastructure
            <br />
            <span className="text-neutral-500">for the AI Era</span>
          </h1>
          <p className="text-xl text-neutral-600 mb-8">
            Register intellectual property rights, manage AI training permissions,
            and license creative works with complete provenance tracking.
          </p>
          <div className="flex gap-4">
            <Link
              href="/auth/login"
              className="bg-black text-white px-6 py-3 rounded-lg hover:bg-neutral-800 transition font-medium"
            >
              Get Started
            </Link>
            <Link
              href="/docs"
              className="border border-neutral-300 px-6 py-3 rounded-lg hover:bg-neutral-100 transition font-medium"
            >
              View Documentation
            </Link>
          </div>
        </div>
      </section>

      {/* Feature Grid */}
      <section className="max-w-7xl mx-auto px-6 py-16">
        <div className="border-t border-neutral-200 pt-16">
          <h2 className="text-3xl font-bold mb-12">Core Capabilities</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            {/* Rights Registry */}
            <div className="p-6 border border-neutral-200 rounded-xl bg-white">
              <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center mb-4">
                <svg className="w-5 h-5 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
              </div>
              <h3 className="font-semibold text-lg mb-2">Rights Registry</h3>
              <p className="text-neutral-600">
                Register musical works, sound recordings, voice likenesses,
                character IP, and visual works with industry-standard identifiers.
              </p>
            </div>

            {/* AI Permissions */}
            <div className="p-6 border border-neutral-200 rounded-xl bg-white">
              <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center mb-4">
                <svg className="w-5 h-5 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                </svg>
              </div>
              <h3 className="font-semibold text-lg mb-2">AI Permissions</h3>
              <p className="text-neutral-600">
                Define granular permissions for AI training, generation,
                style transfer, voice cloning, and derivative works.
              </p>
            </div>

            {/* Governance */}
            <div className="p-6 border border-neutral-200 rounded-xl bg-white">
              <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center mb-4">
                <svg className="w-5 h-5 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <h3 className="font-semibold text-lg mb-2">Governance Pipeline</h3>
              <p className="text-neutral-600">
                Proposal-based workflow for rights changes with configurable
                auto-approval rules and audit trail.
              </p>
            </div>

            {/* Licensing */}
            <div className="p-6 border border-neutral-200 rounded-xl bg-white">
              <div className="w-10 h-10 bg-orange-100 rounded-lg flex items-center justify-center mb-4">
                <svg className="w-5 h-5 text-orange-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 5v2m0 4v2m0 4v2M5 5a2 2 0 00-2 2v3a2 2 0 110 4v3a2 2 0 002 2h14a2 2 0 002-2v-3a2 2 0 110-4V7a2 2 0 00-2-2H5z" />
                </svg>
              </div>
              <h3 className="font-semibold text-lg mb-2">License Management</h3>
              <p className="text-neutral-600">
                Create license templates, grant licenses to platforms,
                and track usage with per-use billing support.
              </p>
            </div>

            {/* Timeline */}
            <div className="p-6 border border-neutral-200 rounded-xl bg-white">
              <div className="w-10 h-10 bg-red-100 rounded-lg flex items-center justify-center mb-4">
                <svg className="w-5 h-5 text-red-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <h3 className="font-semibold text-lg mb-2">Complete Provenance</h3>
              <p className="text-neutral-600">
                Immutable timeline of all events with before/after states,
                actor tracking, and full audit trail.
              </p>
            </div>

            {/* API */}
            <div className="p-6 border border-neutral-200 rounded-xl bg-white">
              <div className="w-10 h-10 bg-neutral-100 rounded-lg flex items-center justify-center mb-4">
                <svg className="w-5 h-5 text-neutral-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" />
                </svg>
              </div>
              <h3 className="font-semibold text-lg mb-2">REST API</h3>
              <p className="text-neutral-600">
                Full-featured API for programmatic access to rights registry,
                licensing, and usage reporting.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* IP Types */}
      <section className="max-w-7xl mx-auto px-6 py-16">
        <div className="border-t border-neutral-200 pt-16">
          <h2 className="text-3xl font-bold mb-4">Supported IP Types</h2>
          <p className="text-neutral-600 mb-12 max-w-2xl">
            Schema-driven architecture supports any intellectual property type.
            Pre-configured schemas included for common creative works.
          </p>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
            {[
              { name: "Musical Work", icon: "musical_work", category: "music" },
              { name: "Sound Recording", icon: "sound_recording", category: "music" },
              { name: "Voice Likeness", icon: "voice_likeness", category: "voice" },
              { name: "Character IP", icon: "character_ip", category: "character" },
              { name: "Visual Work", icon: "visual_work", category: "visual" },
            ].map((type) => (
              <div
                key={type.icon}
                className="p-4 border border-neutral-200 rounded-lg bg-white text-center"
              >
                <div className="text-sm font-medium">{type.name}</div>
                <div className="text-xs text-neutral-500 mt-1">{type.category}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-neutral-200 mt-16">
        <div className="max-w-7xl mx-auto px-6 py-12">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-6 h-6 bg-black rounded flex items-center justify-center">
                <span className="text-white font-bold text-xs">CH</span>
              </div>
              <span className="text-sm text-neutral-600">Clearinghouse</span>
            </div>
            <div className="text-sm text-neutral-500">
              IP Licensing Infrastructure for the AI Era
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}
