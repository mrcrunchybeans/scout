# Quick Start: Advanced Analytics

## 🎯 Getting Started in 5 Minutes

### Step 1: Open Advanced Analytics Dashboard
1. Navigate to **Reports & Analytics** page
2. Click the **📊** (Advanced Analytics) button in the top right
3. You're in the dashboard!

### Step 2: Pick Your Date Range
- Use quick presets: **7 days**, **30 days**, **90 days**, or **Year**
- Or manually select start/end dates
- Data updates automatically

### Step 3: Choose What to Analyze
**Pick Metrics** (what you want to measure):
- 📦 **Total Usage** - How much was used
- 📊 **Usage Frequency** - How many times
- ⚡ **Velocity** - Usage per day
- 🎯 **Efficiency** - Usage vs waste ratio

**Pick Dimensions** (how to break it down):
- 🏥 **By Intervention** - Different intervention types
- 💰 **By Grant** - Different funding sources
- 👤 **By Operator** - Different staff members
- 📅 **By Date** - Daily/Weekly/Monthly trends

### Step 4: Add Filters (Optional)
Click filter buttons to narrow results:
- Select specific Interventions
- Select specific Grants
- Select specific Operators
- Select specific Categories

### Step 5: Run Analysis
Click **▶️ Run Analysis** button → Results appear instantly!

---

## 📊 Understanding Results

### Result Cards Show:
```
By Intervention (example)
├── Intervention A: 150.25 total (23 uses)
├── Intervention B: 89.50 total (12 uses)
└── Intervention C: 65.00 total (8 uses)
```

### Efficiency Score (0-100):
- 🟢 **70-100**: Optimal - Item is well-managed
- 🟡 **40-69**: Good - Acceptable performance
- 🔴 **<40**: Needs Attention - Review stocking

---

## 🎓 Common Tasks

### Task 1: "I need to know our top 10 items by usage"
1. Select Date Range: 30 days
2. Metrics: Total Usage
3. Dimensions: By Item
4. Run Analysis
✅ See ranked list of items

### Task 2: "Compare grant spending"
1. Select Date Range: This Month
2. Metrics: Total Usage, Usage Frequency
3. Dimensions: By Grant
4. Run Analysis
✅ See breakdown by grant

### Task 3: "Check which staff are most active"
1. Select Date Range: This Month
2. Metrics: Total Usage, Usage Frequency
3. Dimensions: By Operator
4. Optional: Filter by Intervention
5. Run Analysis
✅ See staff activity metrics

### Task 4: "Find inventory efficiency problems"
1. Select Date Range: 90 days
2. Scroll down to **Inventory Efficiency**
3. Look for 🔴 items marked "NEEDS_ATTENTION"
✅ See which items need review

### Task 5: "Export data for further analysis"
1. Run any analysis
2. Look for **Export** button (📥) at top
3. Choose format: CSV, JSON, or TSV
✅ Download file for Excel/other tools

---

## 💡 Tips & Tricks

### Tip 1: Quick Period Comparison
- Generate report for Period 1
- Export to CSV/JSON
- Change dates, generate Period 2
- Compare in Excel

### Tip 2: Focus Analysis
- Use filters to narrow to specific grant
- Analyze single intervention's usage
- Track individual operator performance

### Tip 3: Trend Spotting
- Compare 30-day vs 90-day periods
- Look at efficiency scores over time
- Identify seasonal patterns

### Tip 4: Efficiency Insights
- Red items (Needs Attention) = overstocked or underu sed
- Green items (Optimal) = well-balanced
- Focus improvement efforts on yellow items

### Tip 5: Export for Sharing
Export results as:
- **CSV** → Open in Excel for charts
- **JSON** → Use in other analytics tools
- **TSV** → Direct paste into spreadsheets

---

## 🔧 Advanced Features

### Custom Metric Combinations
Metrics work together for detailed analysis:
```
Scenario: "Track our busiest interventions with efficiency"
✓ Metrics: Total Usage + Efficiency
✓ Dimensions: By Intervention
Result: See which interventions are both high-volume AND efficient
```

### Multi-Dimensional Analysis
Stack multiple dimensions:
```
Scenario: "See which operators are using which grants"
✓ Dimensions: By Operator + By Grant
Result: See intersection of staff and funding sources
```

### Top N Results
Limit results for clarity:
```
Scenario: "Top 5 items"
The system automatically limits to Top 10 for performance
```

---

## 📈 What the Numbers Mean

### Total Usage: 150.25
- Total quantity of items used (in base units)
- Example: 150.25 individual gauze pads

### Usage Frequency: 23
- Number of separate transactions
- Example: 23 different times something was used

### Average Usage: 6.5
- Average quantity per transaction (Total ÷ Frequency)
- Example: ~6.5 items per use

### Velocity: 5.0/day
- Average quantity used per day
- Example: 5 items per day on average

### Efficiency: 85%
- How effective the usage is vs waste
- Higher = better

---

## ❌ Troubleshooting

**Q: No results showing?**
A: 
- Check date range has data
- Verify filters aren't too restrictive
- Try broader date range

**Q: Results look incomplete?**
A:
- System limits to 1,000 records for performance
- Try narrowing date range
- Apply filters to reduce data

**Q: Export file is very large?**
A:
- Use narrower date range
- Apply more filters
- Check "Include details" options

**Q: Efficiency scores seem wrong?**
A:
- Scores based on turnover + overstock balance
- Takes 30+ days of data for accuracy
- May seem low for new items

---

## 📞 Need Help?

See complete documentation: `ANALYTICS_README.md`

For issues or feature requests:
- Check troubleshooting section
- Review ANALYTICS_README.md
- Contact admin team

---

## 🎯 Key Takeaways

✅ **Quick**: Results in seconds  
✅ **Flexible**: Choose exactly what to analyze  
✅ **Clear**: Efficiency scores show at a glance  
✅ **Exportable**: Share data with others  
✅ **Powerful**: Deep analytics capability  

**Start by:** Reports → Advanced Analytics → Pick dates → Pick metrics → Run!
