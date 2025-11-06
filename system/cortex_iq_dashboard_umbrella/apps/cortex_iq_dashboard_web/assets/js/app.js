// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Belgium Map Hook
const BelgiumMap = {
  mounted() {
    const locations = JSON.parse(this.el.dataset.locations)

    // Initialize map centered on Belgium
    this.map = L.map(this.el).setView([50.5, 4.5], 8)

    // Add OpenStreetMap tiles with dark theme
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
      subdomains: 'abcd',
      maxZoom: 20
    }).addTo(this.map)

    // Store location data by city for reference
    this.locationData = {}
    locations.forEach(location => {
      this.locationData[location.city] = location
    })

    // Store markers by city (created dynamically as homes come online)
    this.cityMarkers = {}

    // Store homes by city for click handling
    this.homesByCity = {}

    // Track home count per city for dynamic marker sizing
    this.homeCountByCity = {}

    // Store home states by city for aggregate calculations
    this.homeStatesByCity = {}

    // Handle region filtering
    this.selectedRegion = this.el.dataset.selectedRegion || 'all'
    this.filterMarkersByRegion(this.selectedRegion)

    // Listen for region filter changes
    this.handleEvent("filter_region", ({region}) => {
      this.selectedRegion = region
      this.filterMarkersByRegion(region)
    })

    // Listen for home state updates from server
    this.handleEvent("update_home", ({home_id, city, state}) => {
      // console.log(`[BelgiumMap] Received update for ${home_id} in ${city}`)

      // Track which homes are in which city
      if (!this.homesByCity[city]) {
        this.homesByCity[city] = []
      }
      if (!this.homesByCity[city].includes(home_id)) {
        this.homesByCity[city].push(home_id)
        // console.log(`[BelgiumMap] Added ${home_id} to ${city}. Total homes in city: ${this.homesByCity[city].length}`)
      }

      // Track home count
      this.homeCountByCity[city] = this.homesByCity[city].length

      // Store this home's state for aggregate calculations
      if (!this.homeStatesByCity[city]) {
        this.homeStatesByCity[city] = {}
      }
      this.homeStatesByCity[city][home_id] = state

      // Create marker for this city if it doesn't exist yet
      if (!this.cityMarkers[city]) {
        const location = this.locationData[city]
        if (location) {
          // console.log(`[BelgiumMap] Creating new marker for ${city} at [${location.latitude}, ${location.longitude}]`)
          const marker = L.circleMarker([location.latitude, location.longitude], {
            radius: 5, // Smaller initial size for 1000 homes
            fillColor: '#6b7280', // gray initially
            color: '#fff',
            weight: 1.5, // Thinner border for smaller markers
            opacity: 1,
            fillOpacity: 0.8
          }).addTo(this.map)

          marker.bindPopup(`<b>${city}</b><br/>Homes coming online...`)

          // Handle marker clicks - open detail panel
          marker.on('click', () => {
            const homesInCity = this.homesByCity[city] || []
            if (homesInCity.length > 0) {
              this.pushEvent("select_home", { home_id: homesInCity[0] })
            }
          })

          // Store marker reference
          this.cityMarkers[city] = {
            marker,
            region: location.region,
            location: location
          }
        } else {
          // console.warn(`[BelgiumMap] Location not found for city: "${city}". Available cities:`, Object.keys(this.locationData))
        }
      }

      // Update existing marker
      const cityData = this.cityMarkers[city]
      if (cityData && cityData.marker) {
        const marker = cityData.marker

        // Calculate AGGREGATE net energy for ALL homes in this city
        const cityStates = this.homeStatesByCity[city] || {}
        const homesInCity = Object.keys(cityStates).length
        const aggregateNetEnergy = Object.values(cityStates).reduce((total, homeState) => {
          const production = homeState.production_w || 0
          const consumption = homeState.consumption_w || 0
          return total + (production - consumption)
        }, 0)

        // Log aggregate calculation occasionally
        // if (Math.random() < 0.01) { // 1% sample rate
        //   console.log(`[BelgiumMap] ${city} aggregate: ${aggregateNetEnergy.toFixed(0)}W from ${homesInCity} homes`)
        // }

        // Determine color based on CITY aggregate net energy
        let color
        if (aggregateNetEnergy > 500) {
          color = '#10b981' // green - city is net producing
        } else if (aggregateNetEnergy < -500) {
          color = '#ef4444' // red - city is net consuming
        } else {
          color = '#eab308' // yellow - city is balanced
        }

        marker.setStyle({ fillColor: color })

        // Dynamic marker sizing based on home count
        // With 1000 homes across 40 cities (15-40 per city), use smaller markers
        const homesCount = this.homeCountByCity[city] || 1
        const radius = Math.min(5 + (homesCount / 4), 15) // Scale with homes, max 15px

        // Update popup with home count and aggregate energy
        const location = cityData.location
        const netKw = (aggregateNetEnergy / 1000).toFixed(1)
        const netStatus = aggregateNetEnergy > 500 ? 'producing' :
                         aggregateNetEnergy < -500 ? 'consuming' : 'balanced'
        const popupContent = `
          <b>${city}</b><br/>
          <small>${location.postal_code} - ${location.region}</small><br/>
          <b>${homesCount} home(s) online</b><br/>
          <b>Net: ${netKw} kW (${netStatus})</b><br/>
          <small>Click for details</small>
        `
        marker.setPopupContent(popupContent)

        // Pulse animation
        marker.setRadius(radius + 4)
        setTimeout(() => marker.setRadius(radius), 200)
      }

      // Log stats every 10th home
      // const totalHomes = Object.values(this.homesByCity).reduce((sum, homes) => sum + homes.length, 0)
      // if (totalHomes % 10 === 0) {
      //   console.log(`[BelgiumMap] Stats: ${totalHomes} homes across ${Object.keys(this.cityMarkers).length} cities`)
      // }
    })
  },

  filterMarkersByRegion(region) {
    Object.entries(this.cityMarkers).forEach(([city, cityData]) => {
      const { marker, region: cityRegion } = cityData

      if (region === 'all' || region === cityRegion) {
        // Show markers in selected region
        marker.setStyle({ opacity: 1, fillOpacity: 0.8 })
      } else {
        // Dim markers not in selected region
        marker.setStyle({ opacity: 0.3, fillOpacity: 0.2 })
      }
    })
  },

  destroyed() {
    if (this.map) {
      this.map.remove()
    }
  }
}

// 3-Phase Power Bar Chart Hook
const PhaseChart = {
  mounted() {
    const l1 = parseFloat(this.el.dataset.l1) || 0
    const l2 = parseFloat(this.el.dataset.l2) || 0
    const l3 = parseFloat(this.el.dataset.l3) || 0

    const options = {
      series: [{
        name: 'Power',
        data: [l1, l2, l3]
      }],
      chart: {
        type: 'bar',
        height: 200,
        background: 'transparent',
        toolbar: { show: false }
      },
      plotOptions: {
        bar: {
          horizontal: true,
          distributed: true
        }
      },
      colors: ['#3b82f6', '#8b5cf6', '#ec4899'],
      dataLabels: {
        enabled: true,
        formatter: val => Math.round(val) + 'W',
        style: { colors: ['#fff'] }
      },
      xaxis: {
        categories: ['L1', 'L2', 'L3'],
        labels: { style: { colors: '#9ca3af' } }
      },
      yaxis: {
        labels: { style: { colors: '#9ca3af' } }
      },
      grid: {
        borderColor: '#374151'
      },
      theme: {
        mode: 'dark'
      },
      legend: { show: false }
    }

    this.chart = new ApexCharts(this.el, options)
    this.chart.render()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

// Power Sparkline Hook
const PowerSparkline = {
  mounted() {
    const history = JSON.parse(this.el.dataset.history)
    const reversed = [...history].reverse()

    const timestamps = reversed.map(h => new Date(h.timestamp).getTime())
    const production = reversed.map(h => h.production_w)
    const consumption = reversed.map(h => h.consumption_w)

    const options = {
      series: [{
        name: 'Production',
        data: production.map((val, idx) => [timestamps[idx], val])
      }, {
        name: 'Consumption',
        data: consumption.map((val, idx) => [timestamps[idx], val])
      }],
      chart: {
        type: 'area',
        height: 150,
        background: 'transparent',
        toolbar: { show: false },
        sparkline: { enabled: false }
      },
      stroke: {
        curve: 'smooth',
        width: 2
      },
      fill: {
        type: 'gradient',
        gradient: {
          shadeIntensity: 1,
          opacityFrom: 0.7,
          opacityTo: 0.3
        }
      },
      colors: ['#10b981', '#ef4444'],
      xaxis: {
        type: 'datetime',
        labels: {
          style: { colors: '#9ca3af' },
          datetimeFormatter: {
            hour: 'HH:mm',
            minute: 'HH:mm:ss'
          }
        }
      },
      yaxis: {
        labels: {
          style: { colors: '#9ca3af' },
          formatter: val => Math.round(val) + 'W'
        }
      },
      grid: {
        borderColor: '#374151'
      },
      theme: {
        mode: 'dark'
      },
      legend: {
        labels: { colors: '#9ca3af' }
      }
    }

    this.chart = new ApexCharts(this.el, options)
    this.chart.render()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

// Battery Sparkline Hook
const BatterySparkline = {
  mounted() {
    const history = JSON.parse(this.el.dataset.history)
    const reversed = [...history].reverse()

    const timestamps = reversed.map(h => new Date(h.timestamp).getTime())
    const battery = reversed.map(h => h.battery_percent)

    const options = {
      series: [{
        name: 'Battery',
        data: battery.map((val, idx) => [timestamps[idx], val])
      }],
      chart: {
        type: 'area',
        height: 150,
        background: 'transparent',
        toolbar: { show: false },
        sparkline: { enabled: false }
      },
      stroke: {
        curve: 'smooth',
        width: 2
      },
      fill: {
        type: 'gradient',
        gradient: {
          shadeIntensity: 1,
          opacityFrom: 0.7,
          opacityTo: 0.3
        }
      },
      colors: ['#3b82f6'],
      xaxis: {
        type: 'datetime',
        labels: {
          style: { colors: '#9ca3af' },
          datetimeFormatter: {
            hour: 'HH:mm',
            minute: 'HH:mm:ss'
          }
        }
      },
      yaxis: {
        min: 0,
        max: 100,
        labels: {
          style: { colors: '#9ca3af' },
          formatter: val => val.toFixed(1) + '%'
        }
      },
      grid: {
        borderColor: '#374151'
      },
      theme: {
        mode: 'dark'
      }
    }

    this.chart = new ApexCharts(this.el, options)
    this.chart.render()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

// Pricing History Chart Hook
const PricingChart = {
  mounted() {
    const history = JSON.parse(this.el.dataset.history)
    const providerName = this.el.dataset.providerName
    const reversed = [...history].reverse()

    const timestamps = reversed.map(h => new Date(h.timestamp).getTime())
    const prices = reversed.map(h => h.price_per_kwh)

    const options = {
      series: [{
        name: 'Price',
        data: prices.map((val, idx) => [timestamps[idx], val])
      }],
      chart: {
        type: 'line',
        height: 200,
        background: 'transparent',
        toolbar: { show: false },
        sparkline: { enabled: false }
      },
      stroke: {
        curve: 'smooth',
        width: 3
      },
      colors: ['#eab308'],
      xaxis: {
        type: 'datetime',
        labels: {
          style: { colors: '#9ca3af' },
          datetimeFormatter: {
            hour: 'HH:mm',
            minute: 'HH:mm:ss'
          }
        }
      },
      yaxis: {
        labels: {
          style: { colors: '#9ca3af' },
          formatter: val => '€' + val.toFixed(4)
        }
      },
      grid: {
        borderColor: '#374151'
      },
      theme: {
        mode: 'dark'
      },
      title: {
        text: providerName,
        align: 'left',
        style: {
          color: '#9ca3af',
          fontSize: '12px'
        }
      }
    }

    this.chart = new ApexCharts(this.el, options)
    this.chart.render()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

// Aggregate Power Chart Hook
const AggregatePowerChart = {
  mounted() {
    const history = JSON.parse(this.el.dataset.history)
    const reversed = [...history].reverse()

    const timestamps = reversed.map(h => new Date(h.timestamp).getTime())
    const production = reversed.map(h => h.total_production_w)
    const consumption = reversed.map(h => h.total_consumption_w)

    const options = {
      series: [{
        name: 'Production',
        data: production.map((val, idx) => [timestamps[idx], val])
      }, {
        name: 'Consumption',
        data: consumption.map((val, idx) => [timestamps[idx], val])
      }],
      chart: {
        type: 'area',
        height: 250,
        background: 'transparent',
        toolbar: { show: false }
      },
      stroke: {
        curve: 'smooth',
        width: 2
      },
      fill: {
        type: 'gradient',
        gradient: {
          shadeIntensity: 1,
          opacityFrom: 0.7,
          opacityTo: 0.3
        }
      },
      colors: ['#10b981', '#ef4444'],
      xaxis: {
        type: 'datetime',
        labels: {
          style: { colors: '#9ca3af' },
          datetimeFormatter: {
            hour: 'HH:mm',
            minute: 'HH:mm:ss'
          }
        }
      },
      yaxis: {
        labels: {
          style: { colors: '#9ca3af' },
          formatter: val => Math.round(val) + 'W'
        }
      },
      grid: {
        borderColor: '#374151'
      },
      theme: {
        mode: 'dark'
      },
      legend: {
        labels: { colors: '#9ca3af' }
      }
    }

    this.chart = new ApexCharts(this.el, options)
    this.chart.render()
  },

  handleEvent(event, payload) {
    if (event === "history_updated") {
      // Update chart with new history data from LiveView
      const history = payload.history
      const reversed = [...history].reverse()
      const timestamps = reversed.map(h => new Date(h.timestamp).getTime())
      const production = reversed.map(h => h.total_production_w)
      const consumption = reversed.map(h => h.total_consumption_w)

      this.chart.updateSeries([{
        name: 'Production',
        data: production.map((val, idx) => [timestamps[idx], val])
      }, {
        name: 'Consumption',
        data: consumption.map((val, idx) => [timestamps[idx], val])
      }])
    }
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

// Market Share Chart Hook
const MarketShareChart = {
  mounted() {
    const homeStates = JSON.parse(this.el.dataset.homeStates)
    const providerStates = JSON.parse(this.el.dataset.providerStates)

    // Count homes per provider
    const providerCounts = {}
    Object.values(homeStates).forEach(state => {
      const provider = state.current_provider
      if (provider) {
        providerCounts[provider] = (providerCounts[provider] || 0) + 1
      }
    })

    const labels = Object.keys(providerCounts).map(id =>
      providerStates[id]?.provider_name || id
    )
    const series = Object.values(providerCounts)

    const options = {
      series: series,
      chart: {
        type: 'donut',
        height: 250,
        background: 'transparent'
      },
      labels: labels,
      colors: ['#3b82f6', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981'],
      theme: {
        mode: 'dark'
      },
      legend: {
        labels: { colors: '#9ca3af' }
      },
      plotOptions: {
        pie: {
          donut: {
            labels: {
              show: true,
              total: {
                show: true,
                label: 'Total Homes',
                color: '#9ca3af'
              }
            }
          }
        }
      }
    }

    this.chart = new ApexCharts(this.el, options)
    this.chart.render()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

// Regional Balance Chart Hook
const RegionalBalanceChart = {
  mounted() {
    const history = JSON.parse(this.el.dataset.history)
    if (history.length === 0) return

    const latest = history[0]
    const regions = latest.regional_data || {}

    const categories = []
    const production = []
    const consumption = []

    Object.entries(regions).forEach(([region, data]) => {
      categories.push(region.charAt(0).toUpperCase() + region.slice(1))
      production.push(Math.round(data.production))
      consumption.push(Math.round(data.consumption))
    })

    const options = {
      series: [{
        name: 'Production',
        data: production
      }, {
        name: 'Consumption',
        data: consumption
      }],
      chart: {
        type: 'bar',
        height: 250,
        background: 'transparent',
        toolbar: { show: false }
      },
      plotOptions: {
        bar: {
          horizontal: false,
          columnWidth: '55%',
          endingShape: 'rounded'
        }
      },
      dataLabels: {
        enabled: false
      },
      colors: ['#10b981', '#ef4444'],
      xaxis: {
        categories: categories,
        labels: { style: { colors: '#9ca3af' } }
      },
      yaxis: {
        labels: {
          style: { colors: '#9ca3af' },
          formatter: val => Math.round(val) + 'W'
        }
      },
      grid: {
        borderColor: '#374151'
      },
      theme: {
        mode: 'dark'
      },
      legend: {
        labels: { colors: '#9ca3af' }
      }
    }

    this.chart = new ApexCharts(this.el, options)
    this.chart.render()
  },

  handleEvent(event, payload) {
    if (event === "history_updated") {
      // Update chart with new history data from LiveView
      const history = payload.history
      if (history.length === 0) return

      const latest = history[0]
      const regions = latest.regional_data || {}

      if (Object.keys(regions).length === 0) return

      const categories = []
      const production = []
      const consumption = []

      Object.entries(regions).forEach(([region, data]) => {
        categories.push(region.charAt(0).toUpperCase() + region.slice(1))
        production.push(Math.round(data.production))
        consumption.push(Math.round(data.consumption))
      })

      this.chart.updateOptions({
        xaxis: {
          categories: categories
        }
      })

      this.chart.updateSeries([{
        name: 'Production',
        data: production
      }, {
        name: 'Consumption',
        data: consumption
      }])
    }
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

// Price Comparison Chart Hook
const PriceComparisonChart = {
  mounted() {
    const providerHistory = JSON.parse(this.el.dataset.providerHistory)

    const series = Object.entries(providerHistory).map(([providerId, history]) => {
      const reversed = [...history].reverse()
      return {
        name: providerId.charAt(0).toUpperCase() + providerId.slice(1),
        data: reversed.map(h => [new Date(h.timestamp).getTime(), h.price_per_kwh])
      }
    })

    const options = {
      series: series,
      chart: {
        type: 'line',
        height: 250,
        background: 'transparent',
        toolbar: { show: false }
      },
      stroke: {
        curve: 'smooth',
        width: 2
      },
      colors: ['#3b82f6', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981'],
      xaxis: {
        type: 'datetime',
        labels: {
          style: { colors: '#9ca3af' },
          datetimeFormatter: {
            hour: 'HH:mm',
            minute: 'HH:mm:ss'
          }
        }
      },
      yaxis: {
        labels: {
          style: { colors: '#9ca3af' },
          formatter: val => '€' + val.toFixed(4)
        }
      },
      grid: {
        borderColor: '#374151'
      },
      theme: {
        mode: 'dark'
      },
      legend: {
        labels: { colors: '#9ca3af' }
      }
    }

    this.chart = new ApexCharts(this.el, options)
    this.chart.render()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

// Savings History Chart Hook
const SavingsHistoryChart = {
  mounted() {
    const savingsHistory = JSON.parse(this.el.dataset.savingsHistory)

    // If no data yet, show placeholder
    if (!savingsHistory || savingsHistory.length === 0) {
      this.el.innerHTML = '<div class="text-gray-400 text-center py-8">Waiting for contract switches...</div>'
      return
    }

    const reversed = [...savingsHistory].reverse()

    const timestamps = reversed.map(h => new Date(h.timestamp).getTime())
    const grossSavings = reversed.map(h => h.gross_savings || 0)
    const commission = reversed.map(h => h.commission || 0)
    const netSavings = reversed.map(h => h.net_savings || 0)

    const options = {
      series: [{
        name: 'Customer Gross Savings',
        data: grossSavings.map((val, idx) => [timestamps[idx], val])
      }, {
        name: 'CortexIQ Commission (20%)',
        data: commission.map((val, idx) => [timestamps[idx], val])
      }, {
        name: 'Customer Net Savings (80%)',
        data: netSavings.map((val, idx) => [timestamps[idx], val])
      }],
      chart: {
        type: 'area',
        height: 300,
        background: 'transparent',
        toolbar: { show: false },
        animations: {
          enabled: true,
          easing: 'easeinout',
          speed: 800
        }
      },
      stroke: {
        curve: 'smooth',
        width: 2
      },
      fill: {
        type: 'gradient',
        gradient: {
          shadeIntensity: 1,
          opacityFrom: 0.7,
          opacityTo: 0.3
        }
      },
      colors: ['#10b981', '#f59e0b', '#3b82f6'],
      xaxis: {
        type: 'datetime',
        labels: {
          style: { colors: '#9ca3af' },
          datetimeFormatter: {
            hour: 'HH:mm',
            minute: 'HH:mm:ss'
          }
        }
      },
      yaxis: {
        labels: {
          style: { colors: '#9ca3af' },
          formatter: val => '€' + val.toFixed(2)
        }
      },
      grid: {
        borderColor: '#374151'
      },
      theme: {
        mode: 'dark'
      },
      legend: {
        labels: { colors: '#9ca3af' },
        position: 'top'
      },
      tooltip: {
        theme: 'dark',
        y: {
          formatter: val => '€' + val.toFixed(2)
        }
      }
    }

    this.chart = new ApexCharts(this.el, options)
    this.chart.render()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

// Auto-dismiss Toast Hook
const AutoDismissToast = {
  mounted() {
    // Auto-dismiss after 3 seconds
    this.timeout = setTimeout(() => {
      this.el.style.opacity = '0'
      this.el.style.transition = 'opacity 300ms ease-out'
      setTimeout(() => {
        this.pushEvent("lv:clear-flash", {})
      }, 300)
    }, 3000)
  },

  destroyed() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }
}

// Homes Map Hook - Hierarchical clustering: city markers at low zoom, individual homes at high zoom
const HomesMap = {
  mounted() {
    const homes = JSON.parse(this.el.dataset.homes || '[]')
    const cities = JSON.parse(this.el.dataset.cities || '[]')

    // Initialize map centered on Benelux
    this.map = L.map(this.el).setView([51.0, 4.5], 7)

    // Add dark OpenStreetMap tiles
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
      attribution: '&copy; OpenStreetMap contributors &copy; CARTO',
      subdomains: 'abcd',
      maxZoom: 20
    }).addTo(this.map)

    // Store markers and data
    this.homes = homes
    this.cities = cities    // City totals from aggregator
    this.markers = {}        // Individual home markers
    this.cityMarkers = {}    // City cluster markers
    this.homesByCity = {}    // Homes grouped by city
    this.currentQuery = ''
    this.minZoomForHomes = 10  // Show individual homes at zoom >= 10

    // Group homes by location (city)
    homes.forEach(home => {
      if (home.latitude && home.longitude && home.city) {
        const city = home.city

        if (!this.homesByCity[city]) {
          this.homesByCity[city] = []
        }
        this.homesByCity[city].push(home)

        // Create individual home marker (don't add to map yet)
        const marker = this.createHomeMarker(home, false)
        this.markers[home.home_id] = marker
      }
    })

    // Create initial city cluster markers
    this.updateCityClusters()

    // Update marker visibility based on zoom level
    this.updateMarkerVisibility()

    // Listen for zoom events
    this.map.on('zoomend', () => {
      this.updateMarkerVisibility()
    })

    // Handle search filtering
    this.handleEvent("filter_homes", ({query}) => {
      this.currentQuery = query
      this.filterMarkers(query)
    })

    // Handle zoom to home
    this.handleEvent("zoom_to_home", ({home_id}) => {
      const marker = this.markers[home_id]
      if (marker) {
        this.map.setView(marker.getLatLng(), 13)  // Zoom to level where markers are visible
        marker.openPopup()
      }
    })

    // Handle real-time city updates
    this.handleEvent("update_city", (cityData) => {
      // Update or add city data in the array
      const existingIndex = this.cities.findIndex(c => c.city_name === cityData.city_name)
      if (existingIndex >= 0) {
        this.cities[existingIndex] = cityData
      } else {
        this.cities.push(cityData)
      }

      // Refresh city cluster markers with updated data
      this.updateCityClusters()

      // Update visibility after cluster refresh
      this.updateMarkerVisibility()
    })

    // Handle new homes (sent via push_event since map has phx-update="ignore")
    this.handleEvent("add_home", (home) => {
      // Check if home has required geolocation data
      if (!home.latitude || !home.longitude || !home.city) {
        console.warn('[HomesMap] Skipping home without geolocation:', home.home_id)
        return
      }

      // Check if marker already exists
      if (this.markers[home.home_id]) {
        console.log('[HomesMap] Home already has marker:', home.home_id)
        return
      }

      console.log('[HomesMap] Adding new home:', home.home_id, 'in', home.city)

      // Add to homes array
      this.homes.push(home)

      // Add to homesByCity grouping
      if (!this.homesByCity[home.city]) {
        this.homesByCity[home.city] = []
      }
      this.homesByCity[home.city].push(home)

      // Create marker (initially not added to map - visibility handled by updateMarkerVisibility)
      const marker = this.createHomeMarker(home, false)
      this.markers[home.home_id] = marker

      // Update city clusters first (recreates city markers)
      this.updateCityClusters()

      // Then update marker visibility (adds city/home markers to map based on zoom)
      this.updateMarkerVisibility()
    })
  },

  updateCityClusters() {
    // Remove existing city markers
    Object.values(this.cityMarkers).forEach(marker => {
      if (this.map.hasLayer(marker)) {
        this.map.removeLayer(marker)
      }
    })
    this.cityMarkers = {}

    // Create city markers based on real-time city data OR fallback to home aggregation
    Object.entries(this.homesByCity).forEach(([city, cityHomes]) => {
      // Try to find real-time city data first
      const cityData = this.cities.find(c => c.city_name === city)

      if (cityData) {
        // Use real-time aggregated data
        this.createCityClusterFromAggregateData(city, cityHomes, cityData)
      } else {
        // Fallback: calculate from individual homes
        this.createCityClusterFromHomes(city, cityHomes)
      }
    })
  },

  createCityClusterFromAggregateData(city, cityHomes, cityData) {
    // Calculate average position for city
    const avgLat = cityHomes.reduce((sum, h) => sum + h.latitude, 0) / cityHomes.length
    const avgLon = cityHomes.reduce((sum, h) => sum + h.longitude, 0) / cityHomes.length

    // Use real-time aggregated data
    const totalHomes = cityData.total_homes || cityHomes.length
    const totalProduction = cityData.total_production_kw || 0
    const totalConsumption = cityData.total_consumption_kw || 0
    const netKw = cityData.net_balance_kw || 0

    // Determine cluster color based on net energy
    let color
    if (netKw > 0.5) {
      color = '#10b981' // green - net producing
    } else if (netKw < -0.5) {
      color = '#ef4444' // red - net consuming
    } else {
      color = '#eab308' // yellow - balanced
    }

    // Create circle marker for city
    const radius = Math.min(8 + (totalHomes / 2), 20)  // Scale with home count
    const marker = L.circleMarker([avgLat, avgLon], {
      radius: radius,
      fillColor: color,
      color: '#fff',
      weight: 2,
      opacity: 1,
      fillOpacity: 0.7
    })

    // Popup content with real-time data
    const netStatus = netKw > 0.5 ? 'producing' : netKw < -0.5 ? 'consuming' : 'balanced'
    const avgBattery = cityData.average_battery_percent ? ` | Battery: ${cityData.average_battery_percent.toFixed(0)}%` : ''
    const popupContent = `
      <div class="text-sm">
        <div class="font-bold text-white text-base">${city}</div>
        <div class="text-gray-300 text-xs mt-1"><strong>${totalHomes} home(s) online</strong></div>
        <div class="text-gray-400 text-xs">Net: ${netKw.toFixed(1)} kW (${netStatus})${avgBattery}</div>
        <div class="text-gray-400 text-xs mt-1">Production: ${totalProduction.toFixed(2)} kW</div>
        <div class="text-gray-400 text-xs">Consumption: ${totalConsumption.toFixed(2)} kW</div>
        <div class="text-green-400 text-xs mt-1">🟢 Real-time data (5s refresh)</div>
        <div class="text-gray-500 text-xs mt-2 italic">Zoom in to see individual homes</div>
      </div>
    `

    marker.bindPopup(popupContent)

    // Handle marker click - zoom to this city
    marker.on('click', () => {
      this.map.setView([avgLat, avgLon], 12)  // Zoom to show individual homes
    })

    this.cityMarkers[city] = marker
  },

  createCityClusterFromHomes(city, cityHomes) {
    // Calculate average position for city
    const avgLat = cityHomes.reduce((sum, h) => sum + h.latitude, 0) / cityHomes.length
    const avgLon = cityHomes.reduce((sum, h) => sum + h.longitude, 0) / cityHomes.length

    // Calculate aggregate stats from individual homes
    const totalHomes = cityHomes.length
    // Use correct field names: _production_w and _consumption_w (in watts)
    const totalProductionW = cityHomes.reduce((sum, h) => sum + (h._production_w || 0), 0)
    const totalConsumptionW = cityHomes.reduce((sum, h) => sum + (h._consumption_w || 0), 0)
    const totalProduction = totalProductionW / 1000  // Convert to kW for display
    const totalConsumption = totalConsumptionW / 1000  // Convert to kW for display
    const netEnergy = totalProductionW - totalConsumptionW  // Already in watts

    // Determine cluster color based on net energy
    let color
    if (netEnergy > 500) {
      color = '#10b981' // green - net producing
    } else if (netEnergy < -500) {
      color = '#ef4444' // red - net consuming
    } else {
      color = '#eab308' // yellow - balanced
    }

    // Create circle marker for city
    const radius = Math.min(8 + (totalHomes / 2), 20)  // Scale with home count
    const marker = L.circleMarker([avgLat, avgLon], {
      radius: radius,
      fillColor: color,
      color: '#fff',
      weight: 2,
      opacity: 1,
      fillOpacity: 0.7
    })

    // Popup content
    const netKw = (netEnergy / 1000).toFixed(1)
    const netStatus = netEnergy > 500 ? 'producing' : netEnergy < -500 ? 'consuming' : 'balanced'
    const popupContent = `
      <div class="text-sm">
        <div class="font-bold text-white text-base">${city}</div>
        <div class="text-gray-300 text-xs mt-1"><strong>${totalHomes} home(s) online</strong></div>
        <div class="text-gray-400 text-xs">Net: ${netKw} kW (${netStatus})</div>
        <div class="text-gray-400 text-xs mt-1">Production: ${totalProduction.toFixed(2)} kW</div>
        <div class="text-gray-400 text-xs">Consumption: ${totalConsumption.toFixed(2)} kW</div>
        <div class="text-gray-500 text-xs mt-2 italic">Zoom in to see individual homes</div>
      </div>
    `

    marker.bindPopup(popupContent)

    // Handle marker click - zoom to this city
    marker.on('click', () => {
      this.map.setView([avgLat, avgLon], 12)  // Zoom to show individual homes
    })

    this.cityMarkers[city] = marker
  },

  updateMarkerVisibility() {
    const currentZoom = this.map.getZoom()

    if (currentZoom >= this.minZoomForHomes) {
      // HIGH ZOOM: Show individual home markers, hide city clusters
      Object.values(this.cityMarkers).forEach(marker => {
        if (this.map.hasLayer(marker)) {
          this.map.removeLayer(marker)
        }
      })

      Object.values(this.markers).forEach(marker => {
        if (!this.map.hasLayer(marker)) {
          marker.addTo(this.map)
        }
      })

      // Re-apply current filter
      this.filterMarkers(this.currentQuery)
    } else {
      // LOW ZOOM: Show city clusters, hide individual home markers
      Object.values(this.markers).forEach(marker => {
        if (this.map.hasLayer(marker)) {
          this.map.removeLayer(marker)
        }
      })

      Object.values(this.cityMarkers).forEach(marker => {
        if (!this.map.hasLayer(marker)) {
          marker.addTo(this.map)
        }
      })
    }
  },

  createHomeMarker(home, addToMap = false) {
    // Extract data from home object (field names from LiveView)
    const batteryPercent = home.state_of_charge_pct || 0
    const productionW = home._production_w || 0
    const consumptionW = home._consumption_w || 0
    const productionKw = productionW / 1000
    const consumptionKw = consumptionW / 1000

    // Determine marker color based on status
    let color = '#6b7280' // gray default
    if (productionW > consumptionW) {
      color = '#10b981' // green - producing
    } else if (consumptionW > productionW) {
      color = '#ef4444' // red - consuming
    } else {
      color = '#eab308' // yellow - balanced
    }

    const marker = L.circleMarker([home.latitude, home.longitude], {
      radius: 6,
      fillColor: color,
      color: '#fff',
      weight: 1.5,
      opacity: 1,
      fillOpacity: 0.8
    })

    // Optionally add to map
    if (addToMap) {
      marker.addTo(this.map)
    }

    // Create popup content as DOM element (not HTML string) so event listeners work
    const popupDiv = document.createElement('div')
    popupDiv.className = 'text-sm'

    const nameDiv = document.createElement('div')
    nameDiv.className = 'font-bold text-white'
    nameDiv.textContent = home.name || 'Home'

    const cityDiv = document.createElement('div')
    cityDiv.className = 'text-gray-300 text-xs'
    cityDiv.textContent = home.city || ''

    const batteryDiv = document.createElement('div')
    batteryDiv.className = 'text-gray-400 text-xs mt-1'
    batteryDiv.textContent = `Battery: ${batteryPercent.toFixed(1)}%`

    const productionDiv = document.createElement('div')
    productionDiv.className = 'text-gray-400 text-xs'
    productionDiv.textContent = `Production: ${productionKw.toFixed(2)} kW`

    const consumptionDiv = document.createElement('div')
    consumptionDiv.className = 'text-gray-400 text-xs'
    consumptionDiv.textContent = `Consumption: ${consumptionKw.toFixed(2)} kW`

    const detailsBtn = document.createElement('button')
    detailsBtn.className = 'mt-2 px-2 py-1 bg-blue-600 hover:bg-blue-500 text-white text-xs rounded'
    detailsBtn.textContent = 'View Details'

    // Store reference to hook for use in event listener
    const hook = this

    // Attach click handler using explicit hook reference
    detailsBtn.addEventListener('click', (event) => {
      console.log('View Details button clicked for home:', home.home_id)
      event.preventDefault()
      event.stopPropagation()
      console.log('Hook reference:', hook)
      console.log('pushEvent function:', typeof hook.pushEvent)
      console.log('Pushing select_home event with home_id:', home.home_id)
      hook.pushEvent("select_home", { home_id: home.home_id })
      console.log('pushEvent called successfully')
    })

    // Assemble popup content
    popupDiv.appendChild(nameDiv)
    popupDiv.appendChild(cityDiv)
    popupDiv.appendChild(batteryDiv)
    popupDiv.appendChild(productionDiv)
    popupDiv.appendChild(consumptionDiv)
    popupDiv.appendChild(detailsBtn)

    // Bind popup with DOM element (not HTML string)
    marker.bindPopup(popupDiv)

    return marker
  },

  filterMarkers(query) {
    const lowerQuery = query.toLowerCase()

    Object.entries(this.markers).forEach(([homeId, marker]) => {
      const home = this.homes.find(h => h.home_id === homeId)

      if (!query || query.length < 2) {
        // Show all markers if no query
        marker.setStyle({ opacity: 1, fillOpacity: 0.8 })
      } else {
        // Check if home matches query
        const matches =
          (home.name && home.name.toLowerCase().includes(lowerQuery)) ||
          (home.location && home.location.toLowerCase().includes(lowerQuery)) ||
          (home.meter_ean && home.meter_ean.toLowerCase().includes(lowerQuery)) ||
          (home.home_id && home.home_id.toLowerCase().includes(lowerQuery))

        if (matches) {
          marker.setStyle({ opacity: 1, fillOpacity: 0.8 })
        } else {
          marker.setStyle({ opacity: 0.2, fillOpacity: 0.1 })
        }
      }
    })
  },

  updated() {
    // Don't recreate map on LiveView updates - map should persist
    // This prevents the map from disappearing when LiveView patches the DOM

    // NOTE: Because the map wrapper has phx-update="ignore", data attributes
    // are NOT updated by LiveView. New homes are sent via push_event("add_home")
    // and handled by the handleEvent callback above.

    /* no-op */ void 0
  },

  destroyed() {
    if (this.map) {
      this.map.remove()
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {BelgiumMap, PhaseChart, PowerSparkline, BatterySparkline, PricingChart, AggregatePowerChart, MarketShareChart, RegionalBalanceChart, PriceComparisonChart, SavingsHistoryChart, AutoDismissToast, HomesMap},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

