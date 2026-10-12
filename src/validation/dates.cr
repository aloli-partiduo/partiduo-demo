# SPDX-License-Identifier: AGPL-3.0-or-later

module PartiduoDemo
  module Validation
    # Dates relatives du format (doc/format-dossiers.adoc), résolues pour un
    # jour de chargement donné : mêmes règles que le chargeur de la
    # distribution.
    struct Dates
      DATE   = /\A(?:(?<abs>\d{4})-(?<am>\d{2})-(?<ad>\d{2})|N(?<ny>[+-]\d+)?-(?<nm>\d{2})-(?<nd>\d{2})|M(?<mm>[+-]\d+)?-(?<md>\d{2}))(?:(?<shift>[+-]\d+)j)?\z/
      DAY    = /\AJ(?<shift>[+-]\d+)?\z/
      PERIOD = /\A(?:(?<abs>\d{4})|N(?<ny>[+-]\d+)?)-(?<month>\d{2})\z/
      YEAR   = /\A(?:(?<abs>\d{4})|N(?<ny>[+-]\d+)?)\z/
      TOKENS = /\{(aaaa|aa|mm|jj|periode|N(?:[+-]\d+)?)\}/
      TOKEN  = /\{[^}]*\}/

      getter today : Time

      def initialize(@today : Time)
      end

      def year : Int32
        @today.year
      end

      def self.date?(text : String) : Bool
        if match = DATE.match(text)
          month = (match["am"]? || match["nm"]? || "01").to_i
          day = (match["ad"]? || match["nd"]? || match["md"]?).to_s.to_i
          1 <= month <= 12 && 1 <= day <= 31
        else
          DAY.matches?(text)
        end
      end

      def self.period?(text : String) : Bool
        match = PERIOD.match(text)
        !match.nil? && 1 <= match["month"].to_i <= 12
      end

      def self.year?(text : String) : Bool
        YEAR.matches?(text)
      end

      # Jetons inconnus d'un texte (`{xyz}`).
      def self.unknown_tokens(text : String) : Array(String)
        text.scan(TOKEN).map(&.[0]).reject { |token| TOKENS.matches?(token) }
      end

      def date(text : String) : Time
        if match = DAY.match(text)
          return @today + (match["shift"]?.try(&.to_i) || 0).days
        end
        match = DATE.match(text) || raise ArgumentError.new("date illisible : #{text}")
        base = if abs = match["abs"]?
                 clamp(abs.to_i, match["am"].to_i, match["ad"].to_i)
               elsif match["nm"]?
                 clamp(year + (match["ny"]?.try(&.to_i) || 0), match["nm"].to_i, match["nd"].to_i)
               else
                 first = Time.utc(@today.year, @today.month, 1).shift(months: match["mm"]?.try(&.to_i) || 0)
                 clamp(first.year, first.month, match["md"].to_i)
               end
        base + (match["shift"]?.try(&.to_i) || 0).days
      end

      def period(text : String) : Time
        match = PERIOD.match(text) || raise ArgumentError.new("période illisible : #{text}")
        Time.utc(match["abs"]?.try(&.to_i) || year + (match["ny"]?.try(&.to_i) || 0), match["month"].to_i, 1)
      end

      def year(text : String) : Int32
        match = YEAR.match(text) || raise ArgumentError.new("année illisible : #{text}")
        match["abs"]?.try(&.to_i) || year + (match["ny"]?.try(&.to_i) || 0)
      end

      # Texte d'un relevé, années `{N-1}`, `{N}` remplacées.
      def expand_years(text : String) : String
        text.gsub(/\{(N(?:[+-]\d+)?)\}/) { |token| year(token[1..-2]).to_s }
      end

      private def clamp(year : Int32, month : Int32, day : Int32) : Time
        Time.utc(year, month, day.clamp(1, Time.days_in_month(year, month)))
      end
    end
  end
end
