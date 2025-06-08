import 'dart:io';
import 'package:flutter_html_to_pdf/flutter_html_to_pdf.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'db/database_helper.dart';

class PDFHelper {
  static Future<void> generateTransactionPdf({
    required Map<String, dynamic> user,
    String categoryFilter = 'All',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    Intl.defaultLocale = 'en_US';

    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) return;
      }
    }

    final allTransactions = await DatabaseHelper.instance.getAllTransactions();

    final filtered = allTransactions.where((tx) {
      final txDate = DateTime.parse(tx['date']);
      final isAfterStart = startDate == null || txDate.isAtSameMomentAs(startDate) || txDate.isAfter(startDate);
      final isBeforeEnd = endDate == null || txDate.isAtSameMomentAs(endDate) || txDate.isBefore(endDate.add(const Duration(days: 1)));
      final matchesType = categoryFilter == 'All' || tx['type'] == categoryFilter;
      return isAfterStart && isBeforeEnd && matchesType;
    }).toList();

    final dateFormatter = DateFormat("dd MMMM yyyy, hh:mm a", "en_US");

    final double incomeTotal = filtered
        .where((t) => t['type'] == 'Income')
        .fold(0.0, (num sum, item) => sum + (double.tryParse(item['amount'].toString()) ?? 0.0));

    final double expenseTotal = filtered
        .where((t) => t['type'] == 'Expense')
        .fold(0.0, (num sum, item) => sum + (double.tryParse(item['amount'].toString()) ?? 0.0));

    final double balance = incomeTotal - expenseTotal;

    String formatAmount(double amount) =>
        amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);

    final tableRows = filtered.map((tx) {
      final formattedDate = dateFormatter.format(DateTime.parse(tx['date']));
      return """
        <tr>
          <td>$formattedDate</td>
          <td>${tx['amount']}</td>
          <td>${tx['category']}</td>
          <td>${tx['type']}</td>
          <td>${tx['description'] ?? ''}</td>
        </tr>
      """;
    }).join();

    final htmlContent = """
      <html>
        <head>
          <meta charset="utf-8">
          <style>
            body {
              font-family: 'Noto Sans Bengali', sans-serif;
              padding: 20px;
              font-size: 14px;
              color: #333;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              margin-top: 16px;
            }
            th, td {
              border: 1px solid #333;
              padding: 8px;
              font-size: 12px;
              text-align: left;
            }
            th {
              background-color: #f0f0f0;
            }
            .summary-box {
              margin: 20px auto;
              border: 1px solid #ccc;
              border-radius: 8px;
              padding: 16px;
              max-width: 400px;
              background-color: #f9f9f9;
              box-shadow: 0 0 6px rgba(0,0,0,0.1);
            }
            .summary-box h3 {
              margin-top: 0;
              text-align: center;
              color: #444;
            }
            .summary-item {
              display: flex;
              justify-content: space-between;
              margin: 8px 0;
              font-weight: bold;
            }
          </style>
        </head>
        <body>
          <h2>Transaction Report - ${DateTime.now().year}</h2>
          <p>User: ${user['name']}</p>

          <div class="summary-box">
            <h3>Balance Summary</h3>
            <div class="summary-item"><span>Total Income:</span> <span>৳${formatAmount(incomeTotal)}</span></div>
            <div class="summary-item"><span>Total Expenses:</span> <span>৳${formatAmount(expenseTotal)}</span></div>
            <div class="summary-item"><span>Balance:</span> <span>৳${formatAmount(balance)}</span></div>
          </div>

          <table>
            <tr>
              <th>Date</th>
              <th>Amount</th>
              <th>Category</th>
              <th>Type</th>
              <th>Description</th>
            </tr>
            $tableRows
          </table>
        </body>
      </html>
    """;

    final dir = await getApplicationDocumentsDirectory();
    final pdfFile = await FlutterHtmlToPdf.convertFromHtmlContent(
      htmlContent,
      dir.path,
      "transaction_report_${DateTime.now().millisecondsSinceEpoch}",
    );

    await Printing.sharePdf(
      bytes: await pdfFile.readAsBytes(),
      filename: 'transaction_report.pdf',
    );
  }
}
